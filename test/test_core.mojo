from interface.core import (
    Object,
    VTable,
    Interface,
    ObjectPointer,
    to_vtable,
    type_id,
    register_interface,
    lookup_interface,
)

from interface.interfaces import AnyStringable

from testing import (
    assert_equal,
    assert_true,
    assert_not_equal,
    TestSuite,
)


trait Foo:
    fn foo(self) -> Int:
        ...


@fieldwise_init
struct A(Foo):
    var x: Int

    fn foo(self) -> Int:
        return self.x


@fieldwise_init
struct B(Foo):
    var x: Int

    fn foo(self) -> Int:
        return self.x


__extension B(Stringable):
    fn __str__(self) -> String:
        return "B with x = " + self.x.__str__()


@register_passable("trivial")
struct AnyFoo(Foo, Interface):
    comptime Trait = Foo

    var _ptr: ObjectPointer
    var vtable: VTable

    fn __init__[T: Foo](out self, ptr: UnsafePointer[T, _]):
        self._ptr = rebind[ObjectPointer](ptr)
        self.vtable = Self.get_vtable[T]()

    @staticmethod
    fn get_vtable[T: Self.Trait]() -> VTable:
        comptime methods = (
            type_id[T],
            T.foo,
        )
        return to_vtable[methods]()

    fn foo(self) -> Int:
        return rebind[fn (ObjectPointer) -> Int](self.vtable[1])(self._ptr)


def test_type_id_uniqueness():
    var a = A(0)
    var obj_a = Object(a)
    var type_id_1 = obj_a.type_id()

    var a2 = A(0)
    var obj_a2 = Object(a2)
    var type_id_2 = obj_a2.type_id()

    assert_equal(type_id_1, type_id_2)
    assert_equal(type_id[A](), type_id_1)
    assert_not_equal(type_id[A](), type_id[B]())

    _ = a
    _ = a2


def test_vtable_uniqueness():
    var a = A(0)
    var obj_a = Object(a)

    var a2 = A(0)
    var obj_a2 = Object(a2)

    assert_equal(obj_a._vtable, obj_a2._vtable)

    _ = a
    _ = a2


def test_interface_dynamic_dispatch():
    var a = A(0)
    var b = B(1)
    var obj_a = AnyFoo(UnsafePointer(to=a))
    var obj_b = AnyFoo(UnsafePointer(to=b))
    assert_equal(obj_a.foo(), 0)
    assert_equal(obj_b.foo(), 1)
    _ = a
    _ = b


def test_register_interface():
    var a = A(42)
    var a2 = A(100)
    var obj_a = AnyFoo(UnsafePointer(to=a))
    var obj_a2 = AnyFoo(UnsafePointer(to=a2))

    register_interface[AnyFoo, A]()
    var vtable_a = lookup_interface[AnyFoo, A]()
    assert_true(vtable_a)
    assert_equal(vtable_a.value(), obj_a.vtable)
    assert_equal(vtable_a.value(), obj_a2.vtable)

    var b = B(7)
    var obj_b = AnyFoo(UnsafePointer(to=b))

    register_interface[AnyFoo, B]()
    var vtable_b = lookup_interface[AnyFoo, B]()
    assert_true(vtable_b)
    assert_equal(vtable_b.value(), obj_b.vtable)
    assert_not_equal(vtable_a.value(), vtable_b.value())


def test_dyn_cast():
    var a = A(6)
    var b = B(7)

    var dyn_foo_objects: List[AnyFoo] = [
        AnyFoo(UnsafePointer(to=a)),
        AnyFoo(UnsafePointer(to=b)),
    ]

    register_interface[AnyStringable, B]()
    for obj in dyn_foo_objects:
        if dyn_str := obj.dyn_cast[AnyStringable]():
            assert_equal(
                dyn_str.value().__str__(), "B with x = " + obj.foo().__str__()
            )
        else:
            assert_equal(obj.foo(), 6)

    _ = a
    _ = b


def main():
    TestSuite.discover_tests[__functions_in_module()]().run()
