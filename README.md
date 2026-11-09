# zig-javascript-bridge

This library creates bindings for accessing Javascript from within a WASM runtime.  For example:

```zig
const zjb = @import("zjb");

export fn main() void {
    zjb.global("console").call("log", .{zjb.constString("Hello from Zig")}, void);
}

```

Is equivalent to this Javascript:
```javascript
console.log("Hello from Zig");
```

## Generated Javascript

The generated Javascript can be retrieved through the `bindgen` helper function in `build.zig`:

```zig
const javascript_bridge = @import("javascript_bridge");

const js_basename = "zjb_extract.js";
const extract_example_out = javascript_bridge.bindgen(b, .{
    .wasm = example.getEmittedBin(),
    .basename = js_basename,
    .classname = "Zjb",
    .module_style = .js, // .js (default) or .esm
    .minify = b.option(bool, "minifyjs", "minify the js bindings") orelse false,
});
```

## Project Status

ZJB is fully functional and is ready to be used in other projects.  However 1.0 will not be tagged until Zig is 1.0, and there is significant enough usage that confidence in the API not needing further changes is high.

## Why

Calling Javascript functions from Zig is a pain.  WASM has restrictions on the function API surface, and how references to the runtime environment (Javascript) can be stored.  So to access Javascript functionality from Zig, you must create: a function in Zig which is friendly to call, a function export, and a function in Javascript which translates into the call you actually want.

This isn't too bad so far, but the Javascript API surface is large, has a lot of variadic functions, and accepts many types.  The result is that your programming loop of just wanting to write code slows down writing a large amount of ill fitting boilerplate whenever you must cross the Zig to Javascript boundary.

This package is clearly inspired by Go's solution to this problem: https://pkg.go.dev/syscall/js  However, there are a few significant deviations to note if you're familiar with that library:

1. Every call from Go's package involves string decoding, garbage creation, and reflection calls.
2. Go has a one size fits all Javascript file, while zjb uses a generator to produce Javascript for the calls you use.
3. Go's garbage collection and finalizers allows for automatically cleaning up references from Go to Javascript, while zjb requires manual Handle releasing.
4. Zig has no runtime, so there's none of Go's weirdness about blocking on the main thread.

## Usage

As of 2026-11-01, zjb is only known to work with Zig 0.17.0.  If you're using an older version of Zig, look at past commits.  If you're looking for a newer version of Zig, check for branches.

zjb supports both `wasm32-freestanding` and `wasm64-freestanding` (Memory64) targets.

The simple folder provides a good template to start from.  You'll need to update to reference to zjb in `build.zig.zon`.  There's currently no release schedule for point releases, so you should use the latest available code.  Eg, copy the entire `simple` folder into your empty project, then run `zig fetch --save=zjb git+https://github.com/scottredig/zig-javascript-bridge`

Call into Javascript using `zjb`, generate the Javascript side code, and then build an html page to combine them.

### Example

An example which demonstrates usage of all of the components of `zjb` is in the example folder.  It includes:

- `src/main.zig` has usage examples for the `zjb` Zig import.
- `build.zig`'s example for how to set up your build file.
- `static` includes HTML and Javascript files to run the example.

`zig build` from inside the example folder builds the example to `zig-out`.  As a webserver is required to view the samples in action, you can instead use `zig build serve` to build and host the example locally.

### Details

Zjb functions which return a value from Javascript require specifying which type is returned.  As arguments or return types to be passed into Javascript, zjb supports:

- `i32`, `i64`, `f32`, `f64`.  These are the only numerical types that are supported by the WebAssembly JavaScript Interface, so you must cast to one of these before passing.
- `comptime_int`, `comptime_float`.  These are valid as arguments, and are passed as f64 to Javascript, which is Javascript's main number type.
- `zjb.Handle`.  The Zig side type for referring to dynamic Javascript values.  Dynamic handles use positive integer IDs (`1, 2, 3...`) stored in Javascript's `_handles` map.  When used as an argument, it is automatically converted into the value held in `_handles`.  When used as a return value, it is automatically added to `_handles`.  Calling `release` removes it from `_handles` and pushes the ID to an internal free list (`_free_handles`) for O(1) recycling, ensuring IDs are reused without unbounded growth or garbage collection overhead.
- `zjb.ConstHandle` as arguments but not return types.  These values are returned by `zjb.constString`, `zjb.global`, and `zjb.fnHandle`.  `ConstHandle`s are partitioned into negative integers (`-1, -2, -3...`) and stored in a separate `_consthandles` map to completely avoid collisions with dynamic handles.  Several values are predefined:
  - `0`: Javascript `null`
  - `-1`: Javascript `undefined`
  - `-2`: Javascript global scope (`window` in browsers)
  - `-3`: Javascript empty string `""`
  - `-4`: `this.exports` (functions and globals exported from Zig)
  - `-5`: `this._fnptr` (callback dispatch table)
  Dynamic `ConstHandle`s ($\le -6$) are memoized upon first use on the Zig side, so they can be used any number of times without churning garbage.  They are never released and remain valid for the lifetime of the program.
- `void` is a valid type for method calls which have no return value.

Zjb supports multiple ways to expose Zig functions to Javascript:
- `zjb.exportFn` exposes the function with the passed name under `Zjb.exports` for Javascript callers.  This supports `zjb.Handle`, so if you pass an object from a Javascript function, a handle will automatically be created and passed into Zig.  It is the responsibility of the Zig function being called to call `release` on any handles in its arguments at the appropriate time to avoid memory leaks.
- `zjb.fnHandle` exposes callbacks for use as arguments to Javascript functions (such as event listeners) without polluting `Zjb.exports`.  It generates a Wasm export prefixed with `zjb_fnptr_` and creates signature-deduplicated factory functions on the Javascript side (`this._fnptr[sig](name)`), so only one generic wrapper is generated per unique function signature rather than per function.
- Zig's `export` keyword on functions works as it always does in WASM, but doesn't support `zjb.Handle` correctly.

Simple Zig global variables can also be exposed to Javascript:
- `zjb.exportGlobal` exposes the variable with the passed address under `Zjb.exports`. This supports `bool`, `i32`, `i64`, `u32`, `u64`, `f32`, and `f64`. Property descriptors with get/set methods provide transparent access.

A few extra notes:


`zjb.string([]const u8)` decodes the slice of memory as a utf-8 string, returning a Handle.  The string will NOT update to reflect changes in the slice in Zig.

`zjb.global` will be set to the value of that global variable the first time it is called.  As it is intended to be used for Javascript objects or classes defined in the global scope, that usage will be safe.  For example, `console`, `document` or `Map`.  If you use it to retrieve a value or object you've defined in Javascript, ensure it's defined before your program runs and doesn't change.

The \_ArrayView functions (`i8ArrayView`, `u8ArrayView`, etc) create the respective JavaScript typed array backed by the same memory as the Zig WASM instance.

`dataView` is similar in functionality to the ArrayView functions, but returns a DataView object.  Accepts any pointer or slice.

The generated Javascript also includes a shortcut function named `dataView` to get an up-to-date cached `DataView` of the entire WebAssembly `Memory`. 

> [!CAUTION]
> There are three important notes about using the \_ArrayView and dataView functions:
>
> The \_ArrayView and dataView functions will accept const values.  If you pass one (such as []const u8), you are exposing Zig's memory to Javascript.  Changing the values from Javascript may lead to undefined behavior.  Zjb allows this as there are plenty of use cases which only read the data, and requiring non-const values throughout your program if they are eventually passed to Javascript isn't a desirable API.  It's up to you to be safe here.
>
> Changes to the values in either Zig or Javascript will be visible in the other.  HOWEVER, if the wasm memory grows for whatever reason (either through a direct @wasmMemoryGrow call or through allocators), all \_ArrayViews and DataViews are invalided, and their length will be zero.  You have (roughly speaking) three choices to handle this:
> 1. Always create just before using, and release immediately after use.
> 1. Never allocate after using these functions.
> 1. Check their length before any use, if it does not match the intended length, release and recreate the Handle.
>
> Javascripts's DataView allows pulling out arbitrary values from offsets.  This may be useful for working with Zig structs from Javascript, however remember that Zig may reorder the fields for structs.  Use `extern struct` to be safe here.

## How

To solve the general problem of referencing Javascript objects from Zig, handles are mapped on the Javascript side with integer indices:
- Dynamic `Handle`s use positive integers ($1, 2, 3\dots$) stored in a `_handles` `Map`. When released, IDs are recycled via an internal `_free_handles` array for O(1) reuse.
- Static `ConstHandle`s use negative integers ($-1, -2, -3\dots$) stored in a separate `_consthandles` `Map` to prevent collisions.
- Method calls and property lookups pass method names as memoized `ConstHandle` strings (`constString`), unifying import signatures and keeping generated code minimal.

zjb works with two steps:

1. Your Zig code calls zjb functions. Comptime generates specialized export and import signatures so only methods actually used are included in the WASM file.
2. Run an extract methods program on the WASM file (`bindgen`), producing a Javascript class matching your WASM imports and exports. The minimal example above produces this output:

```javascript
const Zjb = class {
  nh(value) {
    if (value === null) {
      return 0;
    }
    if (value === undefined) {
      return -1;
    }
    const result = this._free_handles.length > 0 ? this._free_handles.pop() : this._next_handle++;
    this._handles.set(result, value);
    return result;
  }
  nch(value) {
    if (value === null) {
      return 0;
    }
    if (value === undefined) {
      return -1;
    }
    const result = this._next_const_handle;
    this._consthandles.set(result, value);
    this._next_const_handle++;
    return -1 * result;
  }
  gh(id) {
    if (id > 0) {
      return this._handles.get(id);
    } else {
      return this._consthandles.get(-1 * id);
    }
  }
  dh(id) {
    if (id <= 0) return false;
    const deleted = this._handles.delete(id);
    if (deleted) {
      this._free_handles.push(id);
    }
    return deleted;
  }
  dataView() {
    if (this._cached_data_view.buffer.byteLength !== this.instance.exports.memory.buffer.byteLength) {
      this._cached_data_view = new DataView(this.instance.exports.memory.buffer);
    }
    return this._cached_data_view;
  }

  constructor() {
    this._decoder = new TextDecoder();
    this.imports = {
      "call_o_v": (id0, id1, arg0) => {
        this.gh(id0)[this.gh(id1)](this.gh(arg0));
      },
      "constString": (ptr, len) => {
        return this.nch(this._decoder.decode(new Uint8Array(this.instance.exports.memory.buffer, Number(ptr), Number(len))));
      },
      "get_o": (id0, id1) => {
        return this.nh(this.gh(id0)[this.gh(id1)]);
      },
    };
    this.exports = {
    };
    this._fnptr = {
    };
    this.instance = null;
    this._cached_data_view = null;
    this._export_reverse_handles = {};
    this._free_handles = [];
    this._handles = new Map();
    this._consthandles = new Map();
    this._consthandles.set(0, null);
    this._consthandles.set(1, undefined);
    this._consthandles.set(2, window);
    this._consthandles.set(3, "");
    this._consthandles.set(4, this.exports);
    this._consthandles.set(5, this._fnptr);
    this._next_handle = 1;
    this._next_const_handle = 6;
  }
  setInstance(instance) {
    this.instance = instance;
    const initialView = new DataView(instance.exports.memory.buffer);
    this._cached_data_view = initialView;
  }
};

```
