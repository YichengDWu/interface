from compile import get_type_name
from sys.ffi import _Global
from builtin.rebind import downcast
from hashlib import default_comp_time_hasher

comptime TypeID = SIMD[DType.uint64, 1]
comptime InterfaceTypeID = SIMD[DType.uint64, 2]
comptime ObjectPointer = OpaquePointer[MutOrigin.external]
comptime MethodImpl = OpaquePointer[ImmutOrigin.external]
comptime StaticPointer[T: AnyType] = UnsafePointer[T, StaticConstantOrigin]
comptime VTable = StaticPointer[MethodImpl]

comptime INTERFACE_TABLE = _Global[
    StorageType = Dict[InterfaceTypeID, VTable],
    "INTERFACE_TABLE",
    Dict[InterfaceTypeID, VTable].__init__,
]


@always_inline
fn type_id[T: AnyType]() -> TypeID:
    comptime value = hash[HasherType=default_comp_time_hasher](
        get_type_name[T, qualified_builtins=True]()
    )
    return value


@always_inline
fn global_constant_ptr[T: AnyType, //, value: T]() -> StaticPointer[T]:
    return {__mlir_op.`pop.global_constant`[value=value]()}


@always_inline
fn to_vtable[methods: Tuple]() -> VTable:
    return global_constant_ptr[methods]().bitcast[MethodImpl]()


trait Interface(ImplicitlyCopyable, Movable):
    """A base interface trait for all interfaces.

    Conventionally, an interface struct should have the following layout:
        var : ObjectPointer
        var : VTable

    The `VTable` should have the following layout:
        Index 0: `type_id` function.
        Index 1: `__del__` function.
        Index 2..N: methods of Self.Trait.
    """

    comptime Trait: type_of(AnyType)

    # var _ptr: ObjectPointer
    # var vtable: VTable

    fn __init__[T: Self.Trait](out self, ptr: UnsafePointer[T, _]):
        ...
        # self._ptr = rebind[ObjectPointer](ptr)
        # self._vtable = Self.get_vtable[T]()

    @staticmethod
    fn get_vtable[T: Self.Trait]() -> VTable:
        ...

    @always_inline
    fn get_ptr(self) -> ObjectPointer:
        return rebind[Object](self)._ptr

    @always_inline
    fn get_vtable(self) -> VTable:
        return rebind[Object](self)._vtable

    @always_inline
    fn type_id(self) -> TypeID:
        return rebind[fn () -> TypeID](self.get_vtable()[0])()

    @always_inline
    fn free(deinit self):
        rebind[fn (ObjectPointer)](self.get_vtable()[1])(self.get_ptr())

    fn dyn_cast[Iface: Interface](self) raises -> Optional[Iface]:
        var vtable = lookup_interface(type_id[Iface](), self.type_id())
        if not vtable:
            return None
        return {rebind[Iface](Object(self.get_ptr(), vtable.value()))}


@fieldwise_init
struct Object(Interface):
    comptime Trait = Movable
    var _ptr: ObjectPointer
    var _vtable: VTable

    fn __init__[T: Self.Trait](out self, ptr: UnsafePointer[T, _]):
        self._ptr = rebind[ObjectPointer](ptr)
        self._vtable = Self.get_vtable[T]()

    fn __init__[T: Self.Trait](out self, var value: T):
        var ptr = alloc[T](1)
        ptr.init_pointee_move(value^)
        self._ptr = rebind[ObjectPointer](ptr)
        self._vtable = Self.get_vtable[T]()

    @always_inline
    @staticmethod
    fn get_vtable[T: Self.Trait]() -> VTable:
        comptime methods = (type_id[T], del_trampoline[T])
        return to_vtable[methods]()


fn register_interface[
    Iface: Interface,
    Type: Iface.Trait,
]() raises:
    comptime interface_name = get_type_name[Iface]()
    comptime type_name = get_type_name[downcast[AnyType, Type]]()

    comptime interface_type_id = SIMD[DType.uint64, 2](
        type_id[Iface](), type_id[Type]()
    )
    var vtable = Iface.get_vtable[Type]()

    var interface_table = INTERFACE_TABLE.get_or_create_ptr()
    # if interface_type_id in interface_table[]:
    #    raise Error(
    #        "VTable for interface: ",
    #        interface_name,
    #        "\n and type: ",
    #        type_name,
    #        "\n is already registered.",
    #    )
    interface_table[][interface_type_id] = vtable


@always_inline
fn lookup_interface[
    Iface: Interface,
    Type: Iface.Trait,
]() raises -> Optional[VTable]:
    return lookup_interface(type_id[Iface](), type_id[Type]())


fn lookup_interface(
    interface_id: TypeID, type_id: TypeID
) raises -> Optional[VTable]:
    var interface_type_id = SIMD[DType.uint64, 2](interface_id, type_id)
    var interface_table = INTERFACE_TABLE.get_or_create_ptr()
    return interface_table[].find(interface_type_id)


@always_inline
fn trampoline[
    return_type: AnyType, S: AnyType, //, func: fn (S) -> return_type
](ptr: ObjectPointer) -> return_type:
    return func(ptr.bitcast[S]()[])


fn del_trampoline[T: AnyType](ptr: ObjectPointer):
    var data_ptr = ptr.bitcast[T]()

    @parameter
    if not T.__del__is_trivial:
        data_ptr.destroy_pointee()
    data_ptr.free()
