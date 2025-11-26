from interface import DynStringable
from testing import (
    assert_equal,
    assert_not_equal,
    TestSuite,
)


def test_vtable_uniqueness():
    var a = Int(10)
    var b = Int(20)

    var dyn_a = DynStringable(UnsafePointer(to=a))
    var dyn_b = DynStringable(UnsafePointer(to=b))

    assert_equal(dyn_a.get_vtable(), dyn_b.get_vtable())


def test_interface_dynamic_dispatch():
    var a = Int(12)
    var b = SIMD[DType.uint64, 2](11, 22)
    var dyn_a = DynStringable(UnsafePointer(to=a))
    var dyn_b = DynStringable(UnsafePointer(to=b))
    assert_equal(dyn_a.__str__(), a.__str__())
    assert_equal(dyn_b.__str__(), b.__str__())
    _ = a
    _ = b


def main():
    TestSuite.discover_tests[__functions_in_module()]().run()
