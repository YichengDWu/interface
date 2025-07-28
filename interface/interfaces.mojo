from .core import Interface, VTable


fn str_trampoline[
    return_type: AnyType, S: Stringable, //, func: fn (self: S) -> return_type
](data: OpaquePointer) -> return_type:
    return func(rebind[UnsafePointer[S]](data)[])


@register_passable("trivial")
struct DynStringable(Interface, Stringable):
    alias Trait = Stringable
    var data: OpaquePointer
    var vtable: VTable

    fn __init__[T: Stringable](out self, data: UnsafePointer[T]):
        self.data = data.bitcast[NoneType]()
        self.vtable = VTable.alloc(1)
        self.vtable.init_pointee_copy(
            rebind[OpaquePointer](str_trampoline[T.__str__])
        )

    fn __str__(self) -> String:
        return rebind[fn (OpaquePointer) -> String](self.vtable[0])(self.data)
