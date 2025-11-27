from hashlib import Hasher

from .core import (
    Interface,
    ObjectPointer,
    VTable,
    type_id,
    to_vtable,
    trampoline,
)


struct AnyStringable(Interface, Stringable):
    comptime Trait = Stringable

    var _ptr: ObjectPointer
    var _vtable: VTable

    fn __init__[T: Self.Trait](out self, ptr: UnsafePointer[T, _]):
        self._ptr = rebind[ObjectPointer](ptr)
        self._vtable = Self.get_vtable[T]()

    @staticmethod
    fn get_vtable[T: Self.Trait]() -> VTable:
        comptime methods = (
            type_id[T],
            trampoline[T.__str__],
        )
        return to_vtable[methods]()

    @always_inline
    fn __str__(self) -> String:
        return rebind[fn (ObjectPointer) -> String](self._vtable[1])(self._ptr)


struct AnySized(Interface, Sized):
    comptime Trait = Sized

    var _ptr: ObjectPointer
    var _vtable: VTable

    fn __init__[T: Self.Trait](out self, ptr: UnsafePointer[T, _]):
        self._ptr = rebind[ObjectPointer](ptr)
        self._vtable = Self.get_vtable[T]()

    @staticmethod
    fn get_vtable[T: Self.Trait]() -> VTable:
        comptime methods = (
            type_id[T],
            trampoline[T.__len__],
        )
        return to_vtable[methods]()

    @always_inline
    fn __len__(self) -> Int:
        return rebind[fn (ObjectPointer) -> Int](self._vtable[1])(self._ptr)


@always_inline
fn hash_trampoline[
    S: AnyType, //, func: fn[H: Hasher] (S, mut: H)
](ptr: ObjectPointer, mut hasher: Some[Hasher]):
    func(ptr.bitcast[S]()[], hasher)


struct AnyHashable(Hashable, Interface):
    comptime Trait = Hashable

    var _ptr: ObjectPointer
    var _vtable: VTable

    fn __init__[T: Self.Trait](out self, ptr: UnsafePointer[T, _]):
        self._ptr = rebind[ObjectPointer](ptr)
        self._vtable = Self.get_vtable[T]()

    @staticmethod
    fn get_vtable[T: Self.Trait]() -> VTable:
        comptime methods = (
            type_id[T],
            hash_trampoline[T.__hash__],
        )
        return to_vtable[methods]()

    @always_inline
    fn __hash__[H: Hasher](self, mut hasher: H):
        return rebind[fn (ObjectPointer, mut: H)](self._vtable[1])(
            self._ptr, hasher
        )
