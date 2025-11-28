# Dynamic Interfaces in Mojo

This project implements a lightweight **runtime polymorphism system** for Mojo. It enables dynamic dispatch similar to `std::any` in C++ or `Box<dyn Trait>` in Rust.

By utilizing a global registry and vtables, this library allows you to:

1.  Store heterogeneous types in a single `List` or container.
2.  Perform runtime type erasure and identification.
3.  Dynamically cast objects (`dyn_cast`) between interfaces at runtime.

-----

## Core Concepts

To bridge Mojo's static typing with runtime dynamism, we use four key components:

  * **`Object` (The Container)**
    A type-erased struct (similar to `void*` or `Dyn`). It consists of exactly two pointers: a pointer to the actual data and a pointer to a VTable.

  * **`Interface` (The Trait)**
    The base trait that all dynamic wrappers must implement. It defines the standard memory layout and enforces the implementation of core methods like `type_id()` and `dyn_cast()`.

  * **`VTable` (The Static Map)**
    A **compile-time static array** of function pointers generated for each concrete type.

      * **Index 0:** `type_id` (Unique Type Identifier).
      * **Index 1:** `del_trampoline` (Destructor for memory cleanup).
      * **Index 2+:** User-defined interface methods.

  * **`INTERFACE_TABLE` (The Runtime Registry)**
    A **global dictionary populated at runtime**. It maps the pair `(InterfaceID, ConcreteTypeID)` to the correct VTable. This registry is the lookup engine that makes `dyn_cast` possible.

-----

## Usage Guide

### 1\. Defining Traits and Wrappers

To create a dynamic interface, you must define the standard Mojo trait and a generic struct wrapper that implements `Interface`.

```mojo
from interface.core import (
    Interface, ObjectPointer, VTable, type_id, 
    to_vtable, register_interface, del_trampoline, Object
)

# 1. The Trait Definition
trait Testable(Copyable, Movable):
    fn test(self) -> Int:
        ...

# 2. The Dynamic Wrapper
struct AnyTestable(Interface, Testable):
    comptime Trait = Testable
    var _ptr: ObjectPointer
    var _vtable: VTable

    # Init: Borrows a pointer (Non-owning view)
    fn __init__[T: Self.Trait](out self, ptr: UnsafePointer[T, _]):
        self._ptr = rebind[ObjectPointer](ptr)
        self._vtable = Self.get_vtable[T]()

    @staticmethod
    fn get_vtable[T: Self.Trait]() -> VTable:
        # A "Trampoline" bridges the type-erased ObjectPointer back to the Concrete T
        fn test_trampoline(ptr: ObjectPointer) -> Int:
            return ptr.bitcast[T]()[].test()
        
        # Construct the static VTable
        comptime methods = (
            type_id[T],        # Index 0: ID
            del_trampoline[T], # Index 1: Destructor
            test_trampoline,   # Index 2: Target Method
        )
        return to_vtable[methods]()

    # The Proxy Method
    fn test(self) -> Int:
        # Retrieve function at Index 2 from VTable and call it
        return rebind[fn (ObjectPointer) -> Int](self._vtable[2])(self._ptr)
```

### 2\. Polymorphism

You can now store different concrete structs in the same list and iterate over them transparently.

```mojo
@fieldwise_init
struct Foo(Testable):
    var x: Int
    fn test(self) -> Int: return self.x

@fieldwise_init
struct Bar(Testable):
    var x: Int
    fn test(self) -> Int: return self.x

def main():
    var bar = Bar(6)
    var foo = Foo(7)

    # Polymorphic list storing pointers to stack objects
    var obj_list: List[AnyTestable] = [
        AnyTestable(UnsafePointer(to=bar)),
        AnyTestable(UnsafePointer(to=foo)),
    ]

    for obj in obj_list:
        print(obj.test()) 
    
    # Keep objects alive manually (since we are borrowing)
    _ = bar 
    _ = foo
```

### 3\. Dynamic Casting (`dyn_cast`)

To convert a type-erased object back to a specific interface at runtime, you must register the relationship in the global table.

```mojo
from interface.interfaces import AnyStringable

# Example: Bar also implements Stringable
__extension Bar(Stringable):
    fn __str__(self) -> String:
        return "Bar with x = " + self.x.__str__()

def main():
    # Register relationship: "Bar implements AnyStringable"
    register_interface[AnyStringable, Bar]()

    for obj in obj_list:
        # Attempt runtime cast
        if dyn_str := obj.dyn_cast[AnyStringable]():
            print("Cast Success: " + dyn_str.value().__str__())
        else:
            print("Cast Failed: Object is not a Bar")
```

-----

## Memory Management Models

This library supports two distinct memory models depending on your needs.

### Model A: Manual Management (Borrowed or Explicit Free)

*Best for: Temporary views, performance-critical code, or manual lifecycle control.*

In this model, the wrapper acts as a "dumb" pointer holder. It does not implement `__del__`.

* **Stack Borrowing**: If you wrap a pointer to a stack variable, simply let the wrapper go out of scope. Do not call free.
* **Manual Heap Allocation**: If you manually alloc memory and pass it to the wrapper, you must explicitly call `.free()` to avoid leaks.

**Note on `.free()`**: The Interface trait includes a default `.free()` method. This method works by invoking the function pointer at **Index 1** of the VTable. You must ensure the desctructor is registered at this index for manual freeing to work.

```mojo
# Example of Manual Heap Management

def main():
    # 1. Manually allocate
    var ptr = alloc[Foo](1)
    ptr.init_pointee_move(Foo(42))

    # 2. Wrap (Wrapper takes the pointer but not "ownership" via RAII)
    var obj = AnyTestable(ptr)

    # 3. Use
    print(obj.test())

    # 4. Explicitly Free (Invokes del_trampoline at VTable[1])
    obj.free() 
```

### Model B: Owned (Value Semantics)

*Best for: Passing objects around, return values, and ease of use.*

By implementing **Deep Copy** and **RAII**, the wrapper behaves like a smart pointer that owns its data.

**Implementation:**

1.  **Add a Copy Trampoline** to `get_vtable`.
2.  **Implement `__copyinit__`** to perform deep copies.
3.  **Implement `__del__`** to auto-free memory.

<!-- end list -->

```mojo
struct AnyTestable(Interface, Testable):
    # ... existing fields ...

    @staticmethod
    fn get_vtable[T: Self.Trait]() -> VTable:
        # Define how to clone the concrete type T
        fn copy_trampoline(ptr: ObjectPointer) -> ObjectPointer:
            var new_ptr = alloc[T](1)
            new_ptr.init_pointee_copy(ptr.bitcast[T]()[]) # Deep Copy
            return rebind[ObjectPointer](new_ptr)
        
        comptime methods = (
            type_id[T],        
            del_trampoline[T], 
            test_trampoline,   
            copy_trampoline,   # Index 3: Copy
        )
        return to_vtable[methods]()

    # Owning Constructor
    fn __init__[T: Self.Trait](out self, var value: T):
        var ptr = alloc[T](1)
        ptr.init_pointee_move(value^) # Move to Heap
        self._ptr = rebind[ObjectPointer](ptr)
        self._vtable = Self.get_vtable[T]()

    # Copy Constructor
    fn __copyinit__(out self, other: Self):
        # Call Copy Trampoline (Index 3)
        self._ptr = rebind[fn (ObjectPointer) -> ObjectPointer](other._vtable[3])(other._ptr)
        self._vtable = other._vtable

    # Destructor
    fn __del__(deinit self):
        self.free() # Safe to call now
```

**Usage:**

```mojo
def main():
    # Wrapper takes ownership. No need to keep original variables alive.
    var obj1 = AnyTestable(Foo(100)) 
    
    # Deep copy works automatically
    var obj2 = obj1 
    
    print(obj2.test()) # 100
    
    # Memory is automatically freed when obj1 and obj2 go out of scope.
```