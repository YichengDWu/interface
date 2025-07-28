import interface
from interface import DynObject, DynStringable, register_interface
from testing import assert_equal, assert_true


def test_dynstringable():
    var a = Int(1)
    var b = String("Hello, world!")

    var obj1 = DynObject(UnsafePointer(to=a))
    var obj2 = DynObject(UnsafePointer(to=b))

    register_interface[DynStringable, String]()
    register_interface[DynStringable, Int]()

    var dyn1 = obj1.dyn_cast[DynStringable]()
    var dyn2 = obj2.dyn_cast[DynStringable]()

    assert_true(dyn1)
    assert_true(dyn2)

    assert_equal(dyn1.value().__str__(), "1")
    assert_equal(dyn2.value().__str__(), "Hello, world!")

    _ = a
    _ = b^


def main():
    test_dynstringable()
