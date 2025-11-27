from .core import (
    Object,
    VTable,
    Interface,
    ObjectPointer,
    to_vtable,
    type_id,
    trampoline,
    del_trampoline,
)

from .interfaces import (
    AnyStringable,
    AnySized,
    AnyHashable,
)
