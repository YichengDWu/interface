# Dynamic Interfaces in Mojo

This project provides a proof-of-concept implementation of a dynamic interface system in Mojo, similar to `std::any` in C++ or `Box<dyn Trait>` in Rust. It utilizes a global registry and vtables to allow storing objects of any type in a generic `Object` container and dynamically casting them to specific interfaces at runtime.

### Core Concepts

*   **`Object`**: A type-erased container (similar to `void*` or `Dyn`). It holds a pointer to the data and a basic vtable containing type information. It serves as the root of the dynamic system.
*   **`Interface` Trait**: The base trait that all dynamic interface wrappers must implement. It mandates the storage of an object pointer and a vtable, and provides methods like `type_id()` and `dyn_cast()`.
*   **`VTable` (Virtual Table)**: A static array of function pointers. Index 0 is reserved for the `type_id` function, while subsequent indices store pointers to implementation methods.
*   **Global Registry (`INTERFACE_TABLE`)**: A compile-time global dictionary mapping `(InterfaceID, ConcreteTypeID)` to a specific `VTable`. This enables the runtime resolution of methods when casting.

### How It Works

1.  **Type Erasure**: When you wrap a concrete struct (e.g., `Foo`) into an `Object`, the system stores the pointer and generates a minimal vtable.
2.  **Registration**: You explicitly register which concrete types implement which interfaces using `register_interface`. This populates the global `INTERFACE_TABLE`.
3.  **Dynamic Casting**: When calling `obj.dyn_cast[AnyTrait]()`, the system:
    *   Identifies the ID of the target interface (`AnyTrait`) and the ID of the actual concrete type stored in `obj`.
    *   Lookups this pair in the `INTERFACE_TABLE`.
    *   If a match is found, it returns a new instance of `AnyTrait` pointing to the original data but equipped with the correct VTable for that interface.

### Usage


```mojo
from interface import (
    Interface,
    ObjectPointer,
    VTable,
    type_id,
    to_vtable,
    register_interface,
    del_trampoline
)

# 1. Define a trait
trait Testable(Copyable, Movable):
    fn test(self) -> Int:
        ...


# 2. Define an interface for the trait
struct AnyTestable(Interface, Testable):
    alias Trait = Testable

    var _ptr: ObjectPointer
    var _vtable: VTable

    fn __init__[T: Self.Trait](out self, _ptr: UnsafePointer[T, _]):
        self._ptr = rebind[ObjectPointer](_ptr)
        self._vtable = Self.get_vtable[T]()

    @staticmethod
    fn get_vtable[T: Self.Trait]() -> VTable:
        # Define a trampoline to bridge the opaque pointer to the concrete method
        fn test_trampoline(ptr: ObjectPointer) -> Int:
            return ptr.bitcast[T]()[].test()
        
        comptime methods = (
            type_id[T],
            del_trampoline[T],
            test_trampoline,
        )
        return to_vtable[methods]()

    # The actual interface method calling the vtable
    fn test(self) -> Int:
        # Index 1 corresponds to `test_trampoline` above
        return rebind[fn (ObjectPointer) -> Int](self._vtable[2])(self._ptr)


# 3. Implement concrete types
@fieldwise_init
struct Foo(Testable):
    var x: Int

    fn test(self) -> Int:
        return self.x


@fieldwise_init
struct Bar(Testable):
    var x: Int

    fn test(self) -> Int:
        return self.x


# 4. Main Logic
def main():
    var bar = Bar(6)
    var foo = Foo(7)

    var obj_list: List[AnyTestable] = [
        AnyTestable(UnsafePointer(to=bar)),
        AnyTestable(UnsafePointer(to=foo)),
    ]

    for obj in obj_list:
        print(obj.test())
    # Expected output:
    # 6
    # 7

    _ = bar 
    _ = foo
    
```

### Enabling dynamic casting between interfaces

To enable dynamic casting, call `register_interface`:

```mojo
from interface import AnyStringable

__extension Bar(Stringable):
    fn __str__(self) -> String:
        return "Bar with x = " + self.x.__str__()

def main():
    # ... existing code ...
    register_interface[AnyStringable, Bar]()

    for obj in obj_list:
        if dyn_str := obj.dyn_cast[AnyStringable]():
            print(dyn_str.value().__str__())
        else:
            print("Won't print")

    # Expected Output:
    # Bar with x = 6
    # Won't print

    _ = bar 
    _ = foo
```