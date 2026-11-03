------------------------------------------------------------------------------
--  objloader - a super simple pure-Ada OBJ mesh loader                     --
--                                                                          --
--  Subset: v, vn, vt and f only. Faces are fan-triangulated during parse,  --
--  so a Mesh stores triangles only (concave polygons may triangulate       --
--  wrong). Negative (relative) indices are supported. All other            --
--  directives (mtllib, usemtl, g, o, s, l, free-form geometry) are         --
--  skipped and counted in Stats. The optional fourth vertex component      --
--  (w) and third texture component are ignored.                            --
--                                                                          --
--  Index convention is 1-based, faithful to the OBJ file; 0 marks a        --
--  component absent on a corner.                                           --
--                                                                          --
--  The core parser works on an in-memory String and does no I/O. File      --
--  loading lives in the child package Objloader.Files.                     --
--                                                                          --
--  SPDX-License-Identifier: ISC                                            --
------------------------------------------------------------------------------

with Ada.Containers.Vectors;

package Objloader is

   --  Mesh element type. Callers cast to their own representation (e.g.
   --  fixed point) as needed; no arithmetic is performed on Real by this
   --  library.
   subtype Real is Float;

   --  OBJ indices are 1-based; 0 marks a component absent on a corner.
   subtype Component_Index is Natural;

   type Vertex is record
      X, Y, Z : Real;
   end record;

   type Normal is record
      X, Y, Z : Real;
   end record;

   type Tex_Coord is record
      U, V : Real;
   end record;

   type Corner is record
      V  : Component_Index;  --  position, never 0
      Vt : Component_Index;  --  texture coord, 0 = absent
      Vn : Component_Index;  --  normal,        0 = absent
   end record;

   type Triangle is record
      A, B, C : Corner;
   end record;

   --  Counters filled during parse. Vertices/Normals/Tex_Coords/Triangles
   --  duplicate the corresponding Vector lengths for convenience; the
   --  Ignored_* counters record what the loader dropped, so callers can
   --  detect lossy loads.
   type Stats is record
      Vertices          : Natural;
      Normals           : Natural;
      Tex_Coords        : Natural;
      Triangles         : Natural;
      Ignored_Mtllib    : Natural;
      Ignored_Usemtl    : Natural;
      Ignored_Group     : Natural;
      Ignored_Smoothing : Natural;
      Ignored_Freeform  : Natural;
      Ignored_Unknown   : Natural;
   end record;

   package Vertex_Vectors is
      new Ada.Containers.Vectors (Index_Type => Positive,
                                  Element_Type => Vertex);
   package Normal_Vectors is
      new Ada.Containers.Vectors (Index_Type => Positive,
                                  Element_Type => Normal);
   package Tex_Coord_Vectors is
      new Ada.Containers.Vectors (Index_Type => Positive,
                                  Element_Type => Tex_Coord);
   package Triangle_Vectors is
      new Ada.Containers.Vectors (Index_Type => Positive,
                                  Element_Type => Triangle);

   subtype Vertex_Vector   is Vertex_Vectors.Vector;
   subtype Normal_Vector   is Normal_Vectors.Vector;
   subtype Tex_Coord_Vector is Tex_Coord_Vectors.Vector;
   subtype Triangle_Vector is Triangle_Vectors.Vector;

   --  Visible record on purpose: iterate the Vectors directly.
   type Mesh is record
      Vertices    : Vertex_Vector;
      Normals     : Normal_Vector;
      Tex_Coords  : Tex_Coord_Vector;
      Triangles   : Triangle_Vector;
      Load_Stats  : Stats;
   end record;

   --  Raised by Parse and Objloader.Files.Load on malformed input.
   --  Messages carry the offending line: "line N: ...".
   Objloader_Error : exception;

   --  Parse OBJ text. Data may use LF or CRLF line endings; space, tab,
   --  carriage return and form feed act as separators. Comment and blank
   --  lines are ignored.
   function Parse (Data : String) return Mesh;

   --  Expansion types: a baked triangle soup with one position/uv/normal
   --  per corner, ready for GPU upload. Indices are resolved, so no
   --  index types appear here.
   type Expanded_Vertex is record
      Position       : Vertex;
      UV             : Tex_Coord;
      Surface_Normal : Normal;
   end record;

   type Expanded_Triangle is record
      A, B, C : Expanded_Vertex;
   end record;

   type Expanded_Mesh is array (Positive range <>) of Expanded_Triangle;

   --  Bake M into an array of expanded triangles. Corners lacking vt/vn
   --  get the fill values.
   function Expand
     (M           : Mesh;
      Fill_UV     : Real := 0.0;
      Fill_Normal : Real := 0.0) return Expanded_Mesh;

end Objloader;
