------------------------------------------------------------------------------
--  objloader - file loading implementation.                                --
--                                                                          --
--  SPDX-License-Identifier: ISC                                            --
------------------------------------------------------------------------------

with Ada.Streams.Stream_IO;

package body Objloader.Files is

   function Load (File_Name : String) return Mesh is
      use Ada.Streams;

      File : Stream_IO.File_Type;
   begin
      begin
         Stream_IO.Open (File, Stream_IO.In_File, File_Name);
      exception
         when others =>
            raise Objloader_Error with "cannot open '" & File_Name & "'";
      end;

      declare
         use type Ada.Streams.Stream_IO.Count;

         Size : constant Stream_IO.Count := Stream_IO.Size (File);
         Raw  : Stream_Element_Array (1 .. Stream_Element_Offset (Size));
         Last : Stream_Element_Offset := 0;
         Pos  : Stream_Element_Offset := 1;
      begin
         if Size > Stream_IO.Count (Natural'Last) then
            Stream_IO.Close (File);
            raise Objloader_Error
              with "file too large to load: '" & File_Name & "'";
         end if;
         --  Size (or less) per read until done; the progress guard turns
         --  a truncated file into an error instead of an infinite loop.
         while Pos <= Raw'Last loop
            Stream_IO.Read (File, Raw (Pos .. Raw'Last), Last);
            exit when Last < Pos;
            Pos := Last + 1;
         end loop;

         Stream_IO.Close (File);

         if Pos <= Raw'Last then
            raise Objloader_Error with "short read on '" & File_Name & "'";
         end if;

         declare
            Data : String (1 .. Natural (Size));
         begin
            for I in Raw'Range loop
               Data (Positive (I)) :=
                 Character'Val (Stream_Element'Pos (Raw (I)));
            end loop;
            return Parse (Data);
         end;
      end;
   end Load;

end Objloader.Files;
