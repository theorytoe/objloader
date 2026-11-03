# objloader

A super simple pure-Ada OBJ mesh loader. Standard library only - no C
bindings, no external dependencies.

## Supports

- `v`, `vn`, `vt` and `f` only. Polygon faces are fan-triangulated at
  parse time, so a `Mesh` stores triangles only. Concave polygons may
  triangulate wrong.
- Negative (relative) face indices.
- 1-based indices faithful to the file; `0` marks an absent corner
  component (`vt`/`vn`).
- Everything else - `mtllib`, `usemtl`, `g`, `o`, `s`, `l`, free-form
  geometry, unknown directives - is skipped and counted per kind in
  `Load_Stats`, so lossy loads are detectable.
- Optional fourth `v` component (w) and third `vt` component are
  accepted and ignored.
- LF or CRLF line endings; space, tab, CR and FF act as separators.
- Malformed input raises `Objloader_Error` with messages like
  `line 5: vertex index 4 out of range (1 .. 3)`.
- RM 11.4 gotcha: if you catch the exception in the same body where you
  declared `M : constant Mesh := Load (...)`, the handler does not run -
  declarative-part elaboration raises are only handled by enclosing
  scopes. Assign in the statement part when you need a local catch.

## Usage

```ada
with Objloader.Files;

procedure Example is
   M : constant Objloader.Mesh := Objloader.Files.Load ("cube.obj");
   E : constant Objloader.Expanded_Mesh := Objloader.Expand (M);
begin
   null;  --  E is a GPU-ready triangle soup (position/uv/normal per corner)
end Example;
```

`Parse (Data : String)` does the same on in-memory text and performs no
I/O. The child package `Objloader.Files` is the only unit that touches
the filesystem, which keeps the core portable.

## Build and test

```
alr build
alr exec -- gprbuild -q -P test/objloader_test.gpr
alr exec -- test/bin/test_main
```

Run the driver from the repo root so the fixture paths resolve.

## Limitations

- Fan triangulation only; no ear clipping, no materials, no groups.
- `Real` is `Float` (32-bit); the library performs no arithmetic on it,
  so callers can cast to any target representation (e.g. fixed point)
  after loading.
