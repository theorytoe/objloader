------------------------------------------------------------------------------
--  objloader test driver. Run from the repo root so the fixture paths      --
--  resolve:                                                                --
--     alr exec -- test/bin/objloader_test                                  --
--                                                                          --
--  SPDX-License-Identifier: ISC                                            --
------------------------------------------------------------------------------

with Ada.Command_Line;
with Ada.Exceptions;
with Ada.Text_IO;
with Objloader;
with Objloader.Files;

procedure Test_Main is
   use Ada.Text_IO;
   use Objloader;

   Checks : Natural := 0;
   Failed : Natural := 0;

   procedure Check (Condition : Boolean; Name : String) is
   begin
      Checks := Checks + 1;
      if Condition then
         Put_Line ("ok   " & Name);
      else
         Failed := Failed + 1;
         Put_Line ("FAIL " & Name);
      end if;
   end Check;

   --  Our parse messages always start with "line N:".
   function Has_Line (Msg : String; Want_Line : Positive) return Boolean is
      Want : constant String :=
        "line" & Positive'Image (Want_Line) & ":";
   begin
      return Msg'Length >= Want'Length
        and then Msg (Msg'First .. Msg'First + Want'Length - 1) = Want;
   end Has_Line;

   --  GNAT 16 note: a body's exception handlers do not cover its own
   --  declarative-part elaboration (verified with GNAT 16.1.0 and
   --  16.2.1), so the failing call lives in a nested block inside the
   --  statement part, which the procedure handler does cover.
   procedure Expect_Parse_Error
     (Data : String; Want_Line : Positive) is
   begin
      declare
         M : constant Objloader.Mesh := Objloader.Parse (Data);
         pragma Unreferenced (M);
      begin
         Check (False,
                "expected parse error on line"
                & Positive'Image (Want_Line) & ", got success");
      end;
   exception
      when E : Objloader_Error =>
         Check
           (Has_Line (Ada.Exceptions.Exception_Message (E), Want_Line),
            "parse error on line" & Positive'Image (Want_Line)
            & " (" & Ada.Exceptions.Exception_Message (E) & ")");
   end Expect_Parse_Error;

   procedure Expect_Load_Error
     (Path : String; Want_Line : Positive) is
   begin
      declare
         M : constant Objloader.Mesh := Objloader.Files.Load (Path);
         pragma Unreferenced (M);
      begin
         Check (False, "expected load error for " & Path);
      end;
   exception
      when E : Objloader_Error =>
         Check
           (Has_Line (Ada.Exceptions.Exception_Message (E), Want_Line),
            "load error for " & Path & " on line"
            & Positive'Image (Want_Line)
            & " (" & Ada.Exceptions.Exception_Message (E) & ")");
   end Expect_Load_Error;

   procedure Expect_Open_Error (Path : String) is
   begin
      declare
         M : constant Objloader.Mesh := Objloader.Files.Load (Path);
         pragma Unreferenced (M);
      begin
         Check (False, "expected open error for " & Path);
      end;
   exception
      when Objloader_Error =>
         Check (True, "open error for " & Path);
   end Expect_Open_Error;

   procedure Test_Cube is
      M : constant Objloader.Mesh :=
        Objloader.Files.Load ("test/fixtures/cube.obj");
      E : constant Objloader.Expanded_Mesh := Objloader.Expand (M);
   begin
      Check (Natural (M.Vertices.Length) = 8, "cube vertex count");
      Check (Natural (M.Normals.Length) = 6, "cube normal count");
      Check (Natural (M.Tex_Coords.Length) = 4, "cube texcoord count");
      Check (Natural (M.Triangles.Length) = 12, "cube triangle count");
      Check
        (M.Load_Stats =
           (Vertices         => 8,
            Normals          => 6,
            Tex_Coords       => 4,
            Triangles        => 12,
            Ignored_Mtllib   => 0,
            Ignored_Usemtl   => 0,
            Ignored_Group    => 0,
            Ignored_Smoothing => 0,
            Ignored_Freeform => 0,
            Ignored_Unknown  => 0),
         "cube stats");
      Check (M.Triangles.Element (1) = ((1, 1, 1), (2, 2, 1), (3, 3, 1)),
             "cube fan tri 1");
      Check (M.Triangles.Element (2) = ((1, 1, 1), (3, 3, 1), (4, 4, 1)),
             "cube fan tri 2");
      Check (M.Triangles.Element (12) = ((1, 1, 1), (6, 3, 1), (2, 4, 1)),
             "cube fan tri 12");
      Check (E'Length = 12, "cube expand length");
      Check (E (1).A.Position = (0.5, -0.5, 0.5), "cube expand position");
      Check (E (1).A.UV = (0.0, 0.0), "cube expand uv");
      Check (E (1).A.Surface_Normal = (0.0, 0.0, 1.0), "cube expand normal");
      Check (E (2).B.Position = (-0.5, 0.5, 0.5), "cube expand tri2 mid");
   end Test_Cube;

   procedure Test_Negative is
      M : constant Objloader.Mesh :=
        Objloader.Files.Load ("test/fixtures/negative.obj");
   begin
      Check (Natural (M.Vertices.Length) = 4, "neg vertex count");
      Check (Natural (M.Triangles.Length) = 3, "neg triangle count");
      Check (M.Triangles.Element (1) = ((1, 0, 0), (2, 0, 0), (3, 0, 0)),
             "neg relative quad fan");
      Check (M.Triangles.Element (3) = ((1, 0, 0), (4, 0, 0), (2, 0, 0)),
             "neg mixed indices");
   end Test_Negative;

   procedure Test_Sparse is
      M : constant Objloader.Mesh :=
        Objloader.Files.Load ("test/fixtures/sparse.obj");
      E  : constant Objloader.Expanded_Mesh :=
        Objloader.Expand (M, 1.0, 2.0);
      E2 : constant Objloader.Expanded_Mesh := Objloader.Expand (M);
   begin
      Check (Natural (M.Vertices.Length) = 5, "sparse vertex count");
      Check (Natural (M.Tex_Coords.Length) = 1, "sparse texcoord count");
      Check (Natural (M.Normals.Length) = 1, "sparse normal count");
      Check (Natural (M.Triangles.Length) = 3, "sparse triangle count");
      Check (M.Triangles.Element (1) = ((1, 0, 1), (2, 0, 0), (3, 0, 0)),
             "sparse tri 1 sentinels");
      Check (M.Triangles.Element (3) = ((2, 1, 0), (3, 0, 0), (1, 0, 0)),
             "sparse tri 3 vt only");
      Check (E (1).A.Surface_Normal = (0.0, 0.0, 1.0), "sparse real normal");
      Check (E (1).B.UV = (1.0, 1.0), "sparse fill uv");
      Check (E (1).B.Surface_Normal = (2.0, 2.0, 2.0), "sparse fill normal");
      Check (E (3).A.UV = (0.5, 0.5), "sparse real uv");
      Check (E2 (1).B.UV = (0.0, 0.0), "sparse default fill uv");
      Check (E2 (1).B.Surface_Normal = (0.0, 0.0, 0.0),
             "sparse default fill normal");
   end Test_Sparse;

   procedure Test_Noisy is
      M : constant Objloader.Mesh :=
        Objloader.Files.Load ("test/fixtures/noisy.obj");
   begin
      Check
        (M.Load_Stats =
           (Vertices         => 3,
            Normals          => 0,
            Tex_Coords       => 0,
            Triangles        => 1,
            Ignored_Mtllib   => 1,
            Ignored_Usemtl   => 2,
            Ignored_Group    => 2,
            Ignored_Smoothing => 2,
            Ignored_Freeform => 7,
            Ignored_Unknown  => 1),
         "noisy skip-and-count stats");
      Check (M.Triangles.Element (1) = ((1, 0, 0), (2, 0, 0), (3, 0, 0)),
             "noisy face parsed");
   end Test_Noisy;

   procedure Test_Bad is
   begin
      Expect_Load_Error ("test/fixtures/bad.obj", 5);
   end Test_Bad;

   procedure Test_Inline is
      M1 : constant Objloader.Mesh :=
        Objloader.Parse
          ("v" & ASCII.HT & "0.0" & ASCII.HT & "1.0" & ASCII.HT & "2.0"
           & ASCII.CR & ASCII.LF & "f 1 1 1");
      M2 : constant Objloader.Mesh :=
        Objloader.Parse ("# only a comment" & ASCII.LF
                         & ASCII.CR & ASCII.LF);
      M3 : constant Objloader.Mesh :=
        Objloader.Parse ("vt 0.25 0.5 0.75" & ASCII.LF
                         & "v 1.0 2.0 3.0 1.0" & ASCII.LF);
   begin
      Check (Natural (M1.Vertices.Length) = 1, "inline tabs+crlf vertex");
      Check (Natural (M1.Triangles.Length) = 1, "inline tabs+crlf face");
      Check (M1.Triangles.Element (1).C.V = 1, "inline crlf corner index");
      Check (Natural (M2.Vertices.Length) = 0, "inline comments skipped");
      Check (Natural (M2.Triangles.Length) = 0, "inline comments empty");
      Check (Natural (M3.Tex_Coords.Length) = 1, "inline vt count");
      Check (M3.Tex_Coords.Element (1) = (0.25, 0.5),
             "inline vt third component ignored");
      Check (M3.Vertices.Element (1) = (1.0, 2.0, 3.0),
             "inline v fourth component ignored");

      Expect_Parse_Error ("f 1 2 0" & ASCII.LF, 1);
      Expect_Parse_Error ("v 1.0 2.0 x" & ASCII.LF, 1);
      Expect_Parse_Error ("f 1 2" & ASCII.LF, 1);
      Expect_Parse_Error ("f 1/ 2 3" & ASCII.LF, 1);
      Expect_Parse_Error ("f 1// 2 3" & ASCII.LF, 1);
      Expect_Parse_Error ("f 1/2/ 2 3" & ASCII.LF, 1);
      Expect_Parse_Error ("v 1.0 2.0" & ASCII.LF, 1);
      Expect_Parse_Error ("v 1.0 2.0 3.0 4.0 5.0" & ASCII.LF, 1);
      Expect_Parse_Error ("f -1 -1 -1" & ASCII.LF, 1);
      Expect_Parse_Error ("f 1 2 99" & ASCII.LF, 1);
      Expect_Open_Error ("test/fixtures/does_not_exist.obj");
   end Test_Inline;

begin
   Put_Line ("objloader test driver");
   Test_Cube;
   Test_Negative;
   Test_Sparse;
   Test_Noisy;
   Test_Bad;
   Test_Inline;

   Put_Line (Natural'Image (Checks) & " checks,"
             & Natural'Image (Failed) & " failed");

   if Failed = 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
   else
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Test_Main;
