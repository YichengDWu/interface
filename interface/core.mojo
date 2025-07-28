from compile import get_type_name
from hashlib import Hasher
from sys.ffi import _Global

alias VTable = UnsafePointer[OpaquePointer]


@fieldwise_init
@register_passable("trivial")
struct TraitObject(Copyable, Defaultable, ExplicitlyCopyable, Movable):
    var data: OpaquePointer
    var vtable: VTable

    fn __init__(out self):
        self.data = OpaquePointer()
        self.vtable = VTable()


@register_passable("trivial")
trait Interface(Copyable, Movable):
    alias Trait: __type_of(AnyType)

    # var data: OpaquePointer
    # var vtable: VTable
    fn __init__[T: Self.Trait](out self, data: UnsafePointer[T]):
        pass


@register_passable("trivial")
struct DynObject(Interface):
    alias Trait = AnyType
    var data: OpaquePointer
    var vtable: VTable

    fn __init__[T: AnyType](out self, data: UnsafePointer[T]):
        self.data = data.bitcast[NoneType]()
        self.vtable = VTable.alloc(1)
        self.vtable.init_pointee_copy(
            rebind[OpaquePointer](find_in_registry[T])
        )

    fn query_vtable(self, id: TypeId) -> Optional[VTable]:
        return rebind[fn (TypeId) -> Optional[VTable]](self.vtable[0])(id)

    fn dyn_cast[Iface: Interface](self) -> Optional[Iface]:
        if vtable := self.query_vtable(TypeId.of[Iface]()):
            var u = TraitObject(self.data, vtable.value())
            return rebind[Iface](u)
        return None


fn vtable_for[Iface: Interface, Type: Iface.Trait]() -> VTable:
    var x = Iface(UnsafePointer[Type]())
    return rebind[TraitObject](x).vtable


@fieldwise_init
@register_passable("trivial")
struct TypeId:
    var id: UInt64

    @staticmethod
    fn of[T: AnyType]() -> TypeId:
        return {hash(get_type_name[T]())}


@register_passable("trivial")
struct RegistryKey(KeyElement):
    var value: SIMD[DType.uint64, 2]

    fn __init__(out self, type_id1: TypeId, type_id2: TypeId):
        self.value = SIMD[DType.uint64, 2](type_id1.id, type_id2.id)

    fn __eq__(self, other: Self) -> Bool:
        return all((self.value == other.value))

    fn __ne__(self, other: Self) -> Bool:
        return not (self == other)

    fn __hash__[H: Hasher](self, mut hasher: H):
        hasher.update(self.value)


@fieldwise_init
struct Registry(Copyable, Movable):
    var entries: Dict[RegistryKey, VTable]

    fn register[Iface: AnyType, Type: AnyType](mut self, vtable: VTable):
        self.entries[
            RegistryKey(TypeId.of[Type](), TypeId.of[Iface]())
        ] = vtable

    fn find[Type: AnyType](self, trait_id: TypeId) -> Optional[VTable]:
        return self.entries.get(RegistryKey(TypeId.of[Type](), trait_id))


fn create_registry() -> Registry:
    return Registry(Dict[RegistryKey, VTable]())


alias GLOBAL_REGISTRY = _Global["GLOBAL_REGISTRY", Registry, create_registry]


fn find_in_registry[Type: AnyType](trait_id: TypeId) -> Optional[VTable]:
    return GLOBAL_REGISTRY.get_or_create_ptr()[].find[Type](trait_id)


fn register_interface[Iface: Interface, Type: Iface.Trait]():
    var global_registry_ptr = GLOBAL_REGISTRY.get_or_create_ptr()
    global_registry_ptr[].register[Type, Type](VTable())
    global_registry_ptr[].register[Iface, Type](vtable_for[Iface, Type]())


fn trampoline[
    return_type: AnyType, S: Movable, //, func: fn (self: S) -> return_type
](data: OpaquePointer) -> return_type:
    return func(rebind[UnsafePointer[S]](data)[])
