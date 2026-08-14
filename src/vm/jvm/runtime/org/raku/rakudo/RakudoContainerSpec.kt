package org.raku.rakudo

import java.lang.invoke.MethodHandles
import java.lang.invoke.VarHandle
import java.lang.reflect.Field

import org.raku.nqp.runtime.CallSiteDescriptor
import org.raku.nqp.runtime.Ops
import org.raku.nqp.runtime.ThreadContext
import org.raku.nqp.sixmodel.ContainerSpec
import org.raku.nqp.sixmodel.STable
import org.raku.nqp.sixmodel.SerializationReader
import org.raku.nqp.sixmodel.SerializationWriter
import org.raku.nqp.sixmodel.SixModelObject
import org.raku.nqp.sixmodel.TypeObject

class RakudoContainerSpec : ContainerSpec() {
    companion object {
        /* Container related hints. */
        const val HINT_descriptor = 0
        const val HINT_value = 1

        /* Callsite descriptors. */
        private val STORE = CallSiteDescriptor(
            byteArrayOf(CallSiteDescriptor.ARG_OBJ, CallSiteDescriptor.ARG_OBJ), null)
        private val CAS = CallSiteDescriptor(
            byteArrayOf(CallSiteDescriptor.ARG_OBJ, CallSiteDescriptor.ARG_OBJ, CallSiteDescriptor.ARG_OBJ), null)
    }

    /* Callbacks. */
    @JvmField var store: SixModelObject? = null
    @JvmField var storeUnchecked: SixModelObject? = null
    @JvmField var cas: SixModelObject? = null
    @JvmField var atomicStore: SixModelObject? = null

    /* Fetches a value out of a container. Used for decontainerization. */
    override fun fetch(tc: ThreadContext, cont: SixModelObject): SixModelObject? {
        return cont.get_attribute_boxed(tc, RakOps.key.getGC(tc).Scalar, "\$!value", HINT_value.toLong())
    }
    override fun fetch_i(tc: ThreadContext, cont: SixModelObject): Long {
        return fetch(tc, cont)!!.get_int(tc)
    }
    override fun fetch_n(tc: ThreadContext, cont: SixModelObject): Double {
        return fetch(tc, cont)!!.get_num(tc)
    }
    override fun fetch_s(tc: ThreadContext, cont: SixModelObject): String? {
        return fetch(tc, cont)!!.get_str(tc)
    }

    /* Stores a value in a container. Used for assignment. */
    override fun store(tc: ThreadContext, cont: SixModelObject, obj: SixModelObject) {
        Ops.invokeDirect(tc, store, STORE, arrayOf<Any?>(cont, obj))
    }
    override fun store_i(tc: ThreadContext, cont: SixModelObject, value: Long) {
        store(tc, cont, RakOps.p6box_i(value, tc))
    }
    override fun store_n(tc: ThreadContext, cont: SixModelObject, value: Double) {
        store(tc, cont, RakOps.p6box_n(value, tc))
    }
    override fun store_s(tc: ThreadContext, cont: SixModelObject, value: String?) {
        store(tc, cont, RakOps.p6box_s(value, tc))
    }

    /* Stores a value in a container, without any checking of it (this
     * assumes an optimizer or something else already did it). Used for
     * assignment. */
    override fun storeUnchecked(tc: ThreadContext, cont: SixModelObject, obj: SixModelObject) {
        Ops.invokeDirect(tc, storeUnchecked, STORE, arrayOf<Any?>(cont, obj))
    }

    /* Not all containers are rw (ContainerSpec.canStore() defaults to true). */
    override fun canStore(tc: ThreadContext, cont: SixModelObject): Boolean {
        if (cont !is TypeObject) {
            val desc = cont.get_attribute_boxed(tc, cont.st.WHAT,
                "\$!descriptor", HINT_descriptor.toLong())
            return desc != null
        }
        return false
    }

    /* Name of this container specification. */
    override fun name(): String {
        return "value_desc_cont"
    }

    /* Serializes the container data, if any. */
    override fun serialize(tc: ThreadContext, st: STable, writer: SerializationWriter) {
        writer.writeRef(store)
        writer.writeRef(storeUnchecked)
        writer.writeRef(cas)
        writer.writeRef(atomicStore)
    }

    /* Deserializes the container data, if any. */
    override fun deserialize(tc: ThreadContext, st: STable, reader: SerializationReader) {
        store = reader.readRef()
        storeUnchecked = reader.readRef()
        cas = reader.readRef()
        atomicStore = reader.readRef()
    }

    /* Atomic operations. */

    /* VarHandle for the generated Scalar class's $!value slot (field_1),
     * formerly a sun.misc.Unsafe field offset. Cached lazily from the
     * first container seen, as the Unsafe version cached its offset; the
     * single-field cache also removes that version's two-field publication
     * race (worst case now is a harmless recomputation). */
    private var scalarValueHandle: VarHandle? = null

    private fun ensureAtomicsReady(cont: SixModelObject) {
        if (scalarValueHandle == null) {
            try {
                val field: Field = cont.javaClass.getDeclaredField("field_1")
                field.setAccessible(true)
                scalarValueHandle = MethodHandles.lookup().unreflectVarHandle(field)
            }
            catch (e: Exception) {
                throw RuntimeException(e)
            }
        }
    }

    override fun cas(tc: ThreadContext, cont: SixModelObject,
                     expected: SixModelObject, value: SixModelObject): SixModelObject? {
        Ops.invokeDirect(tc, cas, CAS, arrayOf<Any?>(cont, expected, value))
        return Ops.result_o(tc.curFrame!!)
    }

    override fun atomic_load(tc: ThreadContext, cont: SixModelObject): SixModelObject? {
        ensureAtomicsReady(cont)
        return scalarValueHandle!!.getVolatile(cont) as SixModelObject?
    }

    override fun atomic_store(tc: ThreadContext, cont: SixModelObject, value: SixModelObject) {
        Ops.invokeDirect(tc, atomicStore, STORE, arrayOf<Any?>(cont, value))
    }
}
