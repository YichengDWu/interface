from interface import (
    Interface,
    DynObject,
    VTable,
    trampoline,
    register_interface,
)
from testing import assert_equal, assert_true, assert_false


trait Testable(Copyable, Movable):
    fn test(self) -> UInt32:
        pass


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


@fieldwise_init
struct Bar(Testable):
    fn test(self) -> UInt32:
        return 42


def test_dynamic_register():
    var bar = Bar()
    var obj = DynObject(UnsafePointer(to=bar))
    var dyn1 = obj.dyn_cast[DynTestable]()
    assert_false(dyn1)

    register_interface[DynTestable, Bar]()

    var dyn2 = obj.dyn_cast[DynTestable]()
    assert_true(dyn2)
    assert_equal(dyn2.value().test(), 42)

    _ = bar^


def main():
    test_dynamic_register()
