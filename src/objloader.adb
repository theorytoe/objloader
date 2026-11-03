------------------------------------------------------------------------------
--  objloader - parser implementation. See objloader.ads for the overview.  --
--                                                                          --
--  SPDX-License-Identifier: ISC                                            --
------------------------------------------------------------------------------

package body Objloader is

   --  Separators accepted inside and around lines (CR so CRLF files work
   --  without a special case, FF and TAB for hand-made files).
   function Is_Ws (C : Character) return Boolean is
     (C = ' '
      or else C = ASCII.HT
      or else C = ASCII.CR
      or else C = ASCII.FF);

   --  All parse errors funnel through here so messages have one shape:
   --  "line N: reason". No_Return lets the compiler verify that caller
   --  functions never fall off their end after a failed conversion.
   procedure Error (Line : Positive; Msg : String) with No_Return;

   procedure Error (Line : Positive; Msg : String) is
   begin
      raise Objloader_Error with
        "line" & Positive'Image (Line) & ": " & Msg;
   end Error;

   function To_Real (S : String; Line : Positive) return Real is
   begin
      return Real'Value (S);
   exception
      when Constraint_Error =>
         Error (Line, "bad number '" & S & "'");
   end To_Real;

   function To_Int (S : String; Line : Positive) return Integer is
   begin
      return Integer'Value (S);
   exception
      when Constraint_Error =>
         Error (Line, "bad index '" & S & "'");
   end To_Int;

   --  Map an OBJ face index to a 1-based vector position. Raw = 0 is
   --  never valid in OBJ; Raw < 0 counts back from the current end.
   function Resolve
     (Raw  : Integer;
      Len  : Natural;
      What : String;
      Line : Positive) return Component_Index
   is
      Idx : Integer;
   begin
      if Raw = 0 then
         Error (Line, What & " index 0 is not allowed");
      end if;

      if Raw > 0 then
         Idx := Raw;
      else
         Idx := Len + 1 + Raw;
      end if;

      if Idx < 1 or else Idx > Len then
         Error (Line,
                What & " index" & Integer'Image (Raw)
                & " out of range (1 .." & Natural'Image (Len) & ")");
      end if;

      return Idx;
   end Resolve;

   type Token_Range is record
      First : Natural;
      Last  : Natural;
   end record;

   package Token_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Token_Range);

   --  Split one line on whitespace runs.
   procedure Tokenize
     (Line   : String;
      Tokens : out Token_Vectors.Vector)
   is
      I : Natural := Line'First;
   begin
      Tokens.Clear;
      while I <= Line'Last loop
         if Is_Ws (Line (I)) then
            I := I + 1;
         else
            declare
               Start : constant Natural := I;
            begin
               loop
                  exit when I > Line'Last or else Is_Ws (Line (I));
                  I := I + 1;
               end loop;
               Tokens.Append ((First => Start, Last => I - 1));
            end;
         end if;
      end loop;
   end Tokenize;

   --  Directives we skip because they describe free-form (patch) geometry
   --  or polylines, which this loader does not model.
   function Is_Freeform (Kind : String) return Boolean is
   begin
      return
           Kind = "vp"     or else Kind = "l"
        or else Kind = "cstype" or else Kind = "deg"
        or else Kind = "bmat"   or else Kind = "step"
        or else Kind = "curv"   or else Kind = "curv2"
        or else Kind = "surf"   or else Kind = "end";
   end Is_Freeform;

   function Parse (Data : String) return Mesh is

      M   : Mesh;
      Ign : Stats := (others => 0);

      --  Parse one corner token: "v", "v/vt", "v//vn" or "v/vt/vn",
      --  resolving indices against the vectors built so far.
      function To_Corner (S : String; Line : Positive) return Corner is
         N_Slash : Natural := 0;
         P1, P2  : Natural := 0;
      begin
         for I in S'Range loop
            if S (I) = '/' then
               N_Slash := N_Slash + 1;
               if N_Slash = 1 then
                  P1 := I;
               elsif N_Slash = 2 then
                  P2 := I;
               else
                  Error (Line, "too many '/' in corner '" & S & "'");
               end if;
            end if;
         end loop;

         declare
            function Empty (First, Last : Natural) return Boolean is
              (First > Last);

            Has_Vt : constant Boolean := N_Slash >= 1;
            Has_Vn : constant Boolean := N_Slash >= 2;

            V1_First : constant Natural := S'First;
            V1_Last  : constant Natural :=
              (if N_Slash >= 1 then P1 - 1 else S'Last);

            V2_First : constant Natural := P1 + 1;
            V2_Last  : constant Natural :=
              (if N_Slash >= 2 then P2 - 1 else S'Last);

            V3_First : constant Natural := P2 + 1;
            V3_Last  : constant Natural := S'Last;

            Use_Vt : constant Boolean :=
              Has_Vt and then not Empty (V2_First, V2_Last);
         begin
            if Empty (V1_First, V1_Last) then
               Error (Line, "missing vertex index in corner '" & S & "'");
            end if;

            --  "v/" (trailing slash, empty texture field) is malformed;
            --  "v//vn" (empty texture field in the three-field form) is
            --  the only legal empty field.
            if N_Slash = 1 and then Empty (V2_First, V2_Last) then
               Error (Line, "empty texture field in corner '" & S & "'");
            end if;

            if N_Slash = 2 and then Empty (V3_First, V3_Last) then
               Error (Line, "empty normal field in corner '" & S & "'");
            end if;

            return
              (V  => Resolve
                       (To_Int (S (V1_First .. V1_Last), Line),
                        Natural (M.Vertices.Length), "vertex", Line),
               Vt => (if Use_Vt
                      then Resolve
                             (To_Int (S (V2_First .. V2_Last), Line),
                              Natural (M.Tex_Coords.Length),
                              "texture", Line)
                      else 0),
               Vn => (if Has_Vn
                      then Resolve
                             (To_Int (S (V3_First .. V3_Last), Line),
                              Natural (M.Normals.Length), "normal", Line)
                      else 0));
         end;
      end To_Corner;

      procedure Process_Line (Line : String; Line_No : Positive) is
         Tokens : Token_Vectors.Vector;
      begin
         Tokenize (Line, Tokens);
         if Natural (Tokens.Length) = 0 then
            return;
         end if;

         declare
            Head        : constant Token_Range := Tokens.Element (1);
            Kind        : constant String :=
              Line (Head.First .. Head.Last);
            Token_Count : constant Natural := Natural (Tokens.Length);

            function Val (N : Positive) return Real is
               T : constant Token_Range := Tokens.Element (N);
            begin
               return To_Real (Line (T.First .. T.Last), Line_No);
            end Val;
         begin
            if Kind (Kind'First) = '#' then
               return;
            end if;

            if Kind = "v" then
               if Token_Count not in 4 | 5 then
                  Error (Line_No, "v needs 3 or 4 values");
               end if;
               M.Vertices.Append
                 ((X => Val (2), Y => Val (3), Z => Val (4)));
               --  A fifth token (w) is accepted and ignored.

            elsif Kind = "vn" then
               if Token_Count /= 4 then
                  Error (Line_No, "vn needs 3 values");
               end if;
               M.Normals.Append
                 ((X => Val (2), Y => Val (3), Z => Val (4)));

            elsif Kind = "vt" then
               if Token_Count not in 3 | 4 then
                  Error (Line_No, "vt needs 2 or 3 values");
               end if;
               M.Tex_Coords.Append ((U => Val (2), V => Val (3)));
               --  A fourth token (w) is accepted and ignored.

            elsif Kind = "f" then
               if Token_Count < 4 then
                  Error (Line_No, "face needs at least 3 vertices");
               end if;

               --  Fan-triangulate while streaming: corners 1..n produce
               --  triangles (1, i, i+1) for i in 2 .. n-1.
               declare
                  First_Corner : Corner := (0, 0, 0);
                  Prev_Corner  : Corner := (0, 0, 0);
                  Corner_Count : Natural := 0;
               begin
                  for I in 2 .. Token_Count loop
                     declare
                        T : constant Token_Range := Tokens.Element (I);
                        C : constant Corner :=
                          To_Corner (Line (T.First .. T.Last), Line_No);
                     begin
                        Corner_Count := Corner_Count + 1;
                        if Corner_Count = 1 then
                           First_Corner := C;
                        else
                           if Corner_Count >= 3 then
                              M.Triangles.Append
                                ((First_Corner, Prev_Corner, C));
                           end if;
                           Prev_Corner := C;
                        end if;
                     end;
                  end loop;
               end;

            elsif Kind = "mtllib" then
               Ign.Ignored_Mtllib := Ign.Ignored_Mtllib + 1;
            elsif Kind = "usemtl" then
               Ign.Ignored_Usemtl := Ign.Ignored_Usemtl + 1;
            elsif Kind = "g" or else Kind = "o" then
               Ign.Ignored_Group := Ign.Ignored_Group + 1;
            elsif Kind = "s" then
               Ign.Ignored_Smoothing := Ign.Ignored_Smoothing + 1;
            elsif Is_Freeform (Kind) then
               Ign.Ignored_Freeform := Ign.Ignored_Freeform + 1;
            else
               Ign.Ignored_Unknown := Ign.Ignored_Unknown + 1;
            end if;
         end;
      end Process_Line;

      Pos     : Natural := Data'First;
      Line_No : Positive := 1;

   begin
      while Pos <= Data'Last loop
         declare
            Start : constant Natural := Pos;
            Stop  : Natural := Pos;
         begin
            loop
               exit when Stop > Data'Last or else Data (Stop) = ASCII.LF;
               Stop := Stop + 1;
            end loop;

            Process_Line (Data (Start .. Stop - 1), Line_No);
            Line_No := Line_No + 1;
            Pos := Stop + 1;
         end;
      end loop;

      M.Load_Stats :=
        (Vertices         => Natural (M.Vertices.Length),
         Normals          => Natural (M.Normals.Length),
         Tex_Coords       => Natural (M.Tex_Coords.Length),
         Triangles        => Natural (M.Triangles.Length),
         Ignored_Mtllib   => Ign.Ignored_Mtllib,
         Ignored_Usemtl   => Ign.Ignored_Usemtl,
         Ignored_Group    => Ign.Ignored_Group,
         Ignored_Smoothing => Ign.Ignored_Smoothing,
         Ignored_Freeform => Ign.Ignored_Freeform,
         Ignored_Unknown  => Ign.Ignored_Unknown);
      return M;
   end Parse;

   function Expand_Corner
     (M           : Mesh;
      C           : Corner;
      Fill_UV     : Real;
      Fill_Normal : Real) return Expanded_Vertex
   is
   begin
      return
        (Position => M.Vertices.Element (C.V),
         UV       =>
           (if C.Vt = 0
            then (U => Fill_UV, V => Fill_UV)
            else M.Tex_Coords.Element (C.Vt)),
         Surface_Normal =>
           (if C.Vn = 0
            then (X => Fill_Normal, Y => Fill_Normal, Z => Fill_Normal)
            else M.Normals.Element (C.Vn)));
   end Expand_Corner;

   function Expand
     (M           : Mesh;
      Fill_UV     : Real := 0.0;
      Fill_Normal : Real := 0.0) return Expanded_Mesh
   is
      NT     : constant Natural := Natural (M.Triangles.Length);
      Result : Expanded_Mesh (1 .. NT);
   begin
      for I in 1 .. NT loop
         declare
            T : constant Triangle := M.Triangles.Element (I);
         begin
            Result (I) :=
              (A => Expand_Corner (M, T.A, Fill_UV, Fill_Normal),
               B => Expand_Corner (M, T.B, Fill_UV, Fill_Normal),
               C => Expand_Corner (M, T.C, Fill_UV, Fill_Normal));
         end;
      end loop;
      return Result;
   end Expand;

end Objloader;
