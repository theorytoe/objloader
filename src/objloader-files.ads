------------------------------------------------------------------------------
--  objloader - file loading convenience. Kept in a child package so the    --
--  core parser (and anything embedding it) stays free of I/O.              --
--                                                                          --
--  SPDX-License-Identifier: ISC                                            --
------------------------------------------------------------------------------

package Objloader.Files is

   --  Slurp File_Name fully into memory and parse it. Raises
   --  Objloader_Error when the file cannot be opened or read, or when
   --  its contents do not parse (message carries the offending line).
   function Load (File_Name : String) return Mesh;

end Objloader.Files;
