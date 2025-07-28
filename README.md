# Dynamic Interfaces in Mojo

This project provides a proof-of-concept implementation of a dynamic interface system in Mojo, similar to `std::any` in C++ or trait objects in Rust. It allows you to store objects of any type and dynamically cast them to specific interface types at runtime.

## Core Concepts

*   **`Interface` Trait:** A base trait that all dynamic interfaces must implement.
*   **`DynObject` Struct:** A type-erased container that holds a pointer to the data and a virtual function table (vtable).
*   **`dyn_cast` Method:**  A method on `DynObject` that attempts to cast the stored object to a specified `Interface` type.
*   **Global Registry:** A globally accessible registry that stores the vtables for different type-interface pairs.
*   **`register_interface` Function:** A function to register a new type as an implementation of a specific interface.

## How It Works

1.  **Type Erasure:** A `DynObject` is created from a value of any type. The `DynObject` stores a pointer to the value and a vtable. The vtable is a function pointer that, when called, can retrieve the correct vtable for a given interface type from the global registry.

2.  **Registration:** Before a `DynObject` can be cast to a specific interface, the underlying type must be registered as an implementer of that interface using the `register_interface` function. This function stores the vtable for the `(Type, Interface)` pair in the global registry.

3.  **Dynamic Casting:** The `dyn_cast` method on `DynObject` takes an interface type as a generic argument. It queries the `DynObject`'s vtable with the `TypeId` of the requested interface. If a matching vtable is found in the registry, a new trait object for that interface is created and returned.

## Usage

Here's a simple example from `test/test_core.mojo`:

```mojo
from interface import (
    Interface,
    DynObject,
    VTable,
    trampoline,
    register_interface,
)
from testing import assert_equal, assert_true, assert_false

# 1. Define an interface
trait Testable(Copyable, Movable):
    fn test(self) -> UInt32:
        pass

# 2. Define a dynamic version of the interface
@register_passable("trivial")
struct DynTestable(Interface, Testable):
    alias Trait = Testable
    var data: OpaquePointer
    var vtable: VTable

    fn __init__[T: Testable](out self, data: UnsafePointer[T]):
        self.data = data.bitcast[NoneType]()
        self.vtable = VTable.alloc(1)
        self.vtable.init_pointee_copy(rebind[OpaquePointer](trampoline[T.test]))

    fn test(self) -> UInt32:
        return rebind[fn (OpaquePointer) -> UInt32](self.vtable[0])(self.data)

# 3. Implement the interface for a concrete type
@fieldwise_init
struct Bar(Testable):
    fn test(self) -> UInt32:
        return 42

# 4. Use the dynamic interface system
def test_dynamic_register():
    var bar = Bar()
    var obj = DynObject(UnsafePointer(to=bar))

    # Initially, the cast fails because the interface is not registered
    var dyn1 = obj.dyn_cast[DynTestable]()
    assert_false(dyn1)

    # Register the interface implementation
    register_interface[DynTestable, Bar]()

    # Now, the cast succeeds
    var dyn2 = obj.dyn_cast[DynTestable]()
    assert_true(dyn2)
    assert_equal(dyn2.value().test(), 42)
```


