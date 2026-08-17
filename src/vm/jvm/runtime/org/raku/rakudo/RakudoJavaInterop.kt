package org.raku.rakudo

import org.raku.nqp.runtime.BootJavaInterop
import org.raku.nqp.runtime.CallFrame
import org.raku.nqp.runtime.CallSiteDescriptor
import org.raku.nqp.runtime.CompilationUnit
import org.raku.nqp.runtime.ExceptionHandling
import org.raku.nqp.runtime.GlobalContext
import org.raku.nqp.runtime.Ops
import org.raku.nqp.runtime.ThreadContext
import org.raku.nqp.sixmodel.Boxable
import org.raku.nqp.sixmodel.STable
import org.raku.nqp.sixmodel.SixModelObject

import java.net.MalformedURLException
import java.net.URL
import java.net.URLClassLoader

import java.util.ArrayList
import java.util.Arrays
import java.util.HashMap

import org.raku.rakudo.RakOps.GlobalExt

import java.lang.invoke.CallSite
import java.lang.invoke.MethodHandle
import java.lang.invoke.MethodHandles
import java.lang.invoke.MethodType
import java.lang.invoke.MutableCallSite

import java.lang.reflect.Array as JArray
import java.lang.reflect.Constructor
import java.lang.reflect.Field
import java.lang.reflect.InvocationTargetException
import java.lang.reflect.Method
import java.lang.reflect.Modifier

import org.objectweb.asm.ClassWriter
import org.objectweb.asm.Handle
import org.objectweb.asm.Opcodes
import org.objectweb.asm.Type

open class RakudoJavaInterop(gc: GlobalContext) : BootJavaInterop(gc) {

    class DispatchCallSite : MutableCallSite {

        private var methname: String
        private var handleList: Array<*>? = null
        private var forCtors: Boolean
        private var declaringClass: String? = null
        private var handleDescs: Array<String?>? = null
        private var handlePos = -1
        private var offset = 0
        private var tc: ThreadContext? = null

        @JvmField val fallback: MethodHandle

        companion object {
            /* Written nowhere, read nowhere — preserved from the Java
             * original. */
            @JvmField var scf: CallFrame? = null

            private val FALLBACK: MethodHandle = try {
                MethodHandles.lookup().findVirtual(DispatchCallSite::class.java,
                        "fallback", MethodType.genericMethodType(3, true))
            } catch (e: ReflectiveOperationException) {
                throw LinkageError(e.message, e)
            }
        }

        constructor(methname: String, type: MethodType, handleList: Array<*>) : super(type) {
            this.methname = methname
            this.fallback = FALLBACK.bindTo(this)
            this.handleList = handleList
            this.forCtors = false
        }

        constructor(methname: String, type: MethodType, declaringClass: String) : super(type) {
            this.methname = methname
            this.fallback = FALLBACK.bindTo(this)
            this.forCtors = true
            this.declaringClass = declaringClass
        }

        @Throws(Throwable::class)
        fun parseArgArray(inArgs: Array<Any?>): Array<Any?> {
            // XXX: checking the first arg for concreteness is a hack to identify static methods
            offset = if (forCtors || Ops.isconcrete(inArgs[0] as SixModelObject?, tc!!) == 0L) 1 else 0
            val gcx = RakOps.key.getGC(tc!!)
            val outArgs = arrayOfNulls<Any>(inArgs.size - offset)
            for (i in offset until inArgs.size) {
                if (Ops.islist(inArgs[i] as SixModelObject?, tc!!) == 1L) {
                    outArgs[i - offset] = BootJavaInterop.marshalOutRecursive(inArgs[i] as SixModelObject, tc!!, null)
                }
                else if (Ops.istype(inArgs[i] as SixModelObject?, gcx.List, tc!!) == 1L
                     || Ops.istype(inArgs[i] as SixModelObject?, gcx.Array, tc!!) == 1L) {
                    outArgs[i - offset] = RakudoJavaInterop.marshalOutRecursive(inArgs[i] as SixModelObject, tc!!, null)
                }
                else {
                    outArgs[i - offset] = RakudoJavaInterop.parseSingleArg(inArgs[i] as SixModelObject?, tc!!)
                }
            }
            return outArgs
        }

        @Throws(Throwable::class)
        fun findHandle(parsedArgs: Array<Any?>): Int {
            handlePos = -1
            var descs = handleDescs
            if (descs == null) {
                descs = arrayOfNulls(handleList!!.size)
                for (i in handleList!!.indices) {
                    if (forCtors) {
                        descs[i] = Type.getConstructorDescriptor(handleList!![i] as Constructor<*>)
                    }
                    else {
                        descs[i] = (handleList!![i] as MethodHandle).type().toMethodDescriptorString()
                    }
                }
                handleDescs = descs
            }
            for (i in descs.indices) {
                if (argsMatch(descs[i]!!, parsedArgs)) {
                    handlePos = i
                }
            }
            return handlePos
        }

        fun failDispatch(parsedArgs: Array<Any?>?): Nothing {
            var types = "void"
            var first = true
            if (parsedArgs != null) {
                for (arg in parsedArgs) {
                    if (first) {
                        types = arg!!.javaClass.toString()
                        first = false
                    }
                    else {
                        types += ", " + arg!!.javaClass.toString()
                    }
                }
            }
            throw ExceptionHandling.dieInternal(tc!!,
                "Couldn't find a " + (if (forCtors) "constructor" else "method") + " with types " + types + ".")
        }

        fun argsMatch(desc: String, parsedArgs: Array<Any?>): Boolean {
            var fakeDesc = ""
            for (arg in parsedArgs) {
                fakeDesc += Type.getType(arg!!.javaClass)
            }
            val trimmed = desc.substring(desc.indexOf("(") + 1, desc.lastIndexOf(")"))
            return trimmed == fakeDesc
        }

        @Throws(Throwable::class)
        fun deepArrayCast(obj: Any, type: Type): Any? {
            var elemType = type
            val typeDepth = type.dimensions
            elemType = elemType.elementType

            var objDepth = 0
            var value: Any = obj
            while (value.javaClass.componentType != null) {
                value = (value as Array<*>)[0]!!
                objDepth++
            }

            if (objDepth != typeDepth) {
                return null
            }

            val targetType = castObjectToType(value, elemType)
            if (targetType != null) {
                return deepArrayCast(obj, elemType, type.dimensions)
            }

            return null
        }

        @Throws(Throwable::class)
        fun deepArrayCast(obj: Any, type: Type, depth: Int): Any? {
            var retVal: Any? = null
            var klass: Class<*>? = null
            when (type.sort) {
                Type.BOOLEAN ->
                    klass = java.lang.Boolean.TYPE
                Type.BYTE ->
                    klass = java.lang.Byte.TYPE
                Type.SHORT ->
                    klass = java.lang.Short.TYPE
                Type.INT ->
                    klass = Integer.TYPE
                Type.LONG ->
                    klass = java.lang.Long.TYPE
                Type.CHAR ->
                    klass = Character.TYPE
                Type.FLOAT ->
                    klass = java.lang.Float.TYPE
                Type.DOUBLE ->
                    klass = java.lang.Double.TYPE
                Type.OBJECT ->
                    klass = Class.forName(type.internalName.replace('/', '.'), false, tc!!.gc.byteClassLoader)
                Type.ARRAY -> {}
                else -> {}
            }
            if (depth == 1) {
                retVal = JArray.newInstance(klass, (obj as Array<*>).size)
                for (i in obj.indices) {
                    val value = castObjectToType(obj[i]!!, type)
                    JArray.set(retVal, i, value)
                }
            }
            else {
                for (i in (obj as Array<*>).indices) {
                    val value = deepArrayCast(obj[i]!!, type, depth - 1)
                    if (retVal == null)
                        retVal = JArray.newInstance(value!!.javaClass, obj.size)
                    JArray.set(retVal, i, value)
                }
            }
            return retVal
        }

        @Throws(Throwable::class)
        fun castObjectToType(obj: Any, type: Type): Any? {
            var retVal: Any? = null
            when (type.sort) {
                Type.BOOLEAN -> {
                    if (obj.javaClass == java.lang.Long::class.java) {
                        retVal = (obj as Long) != 0L
                    }
                    else if (obj.javaClass == java.lang.Boolean::class.java) {
                        retVal = obj
                    }
                }
                Type.BYTE ->
                    if (obj.javaClass == java.lang.Long::class.java) {
                        retVal = (obj as Long).toByte()
                    }
                Type.SHORT ->
                    if (obj.javaClass == java.lang.Long::class.java) {
                        retVal = (obj as Long).toShort()
                    }
                Type.INT ->
                    if (obj.javaClass == java.lang.Long::class.java) {
                        retVal = (obj as Long).toInt()
                    }
                Type.LONG ->
                    if (obj.javaClass == java.lang.Long::class.java) {
                        retVal = obj
                    }
                Type.CHAR ->
                    if (obj.javaClass == String::class.java) {
                        retVal = obj
                    }
                Type.FLOAT ->
                    if (obj.javaClass == java.lang.Double::class.java) {
                        retVal = (obj as Double).toFloat()
                    }
                Type.DOUBLE ->
                    if (obj.javaClass == java.lang.Double::class.java) {
                        retVal = obj
                    }
                Type.OBJECT -> {
                    val argType = Class.forName(type.internalName.replace('/', '.'), false, tc!!.gc.byteClassLoader)
                    if (argType.isAssignableFrom(obj.javaClass)) {
                        retVal = obj
                    }
                    else if (argType == java.lang.Boolean::class.java && obj.javaClass == java.lang.Long::class.java) {
                        retVal = (obj as Long) != 0L
                    }
                    else if (argType == java.lang.Byte::class.java && obj.javaClass == java.lang.Long::class.java) {
                        retVal = (obj as Long).toByte()
                    }
                    else if (argType == java.lang.Short::class.java && obj.javaClass == java.lang.Long::class.java) {
                        retVal = (obj as Long).toShort()
                    }
                    else if (argType == java.lang.Integer::class.java && obj.javaClass == java.lang.Long::class.java) {
                        retVal = (obj as Long).toInt()
                    }
                    else if (argType == java.lang.Long::class.java && obj.javaClass == java.lang.Long::class.java) {
                        retVal = obj as Long
                    }
                    else if (argType == java.lang.Float::class.java && obj.javaClass == java.lang.Double::class.java) {
                        retVal = (obj as Double).toFloat()
                    }
                    else if (argType == java.lang.Double::class.java && obj.javaClass == java.lang.Double::class.java) {
                        retVal = obj as Double
                    }
                    else if (argType == Character::class.java && obj.javaClass == String::class.java) {
                        retVal = (obj as String)[0]
                    }
                    else if (argType == String::class.java && obj.javaClass == String::class.java) {
                        retVal = obj as String
                    }
                }
                Type.ARRAY ->
                    if (obj.javaClass.componentType != null) {
                        retVal = deepArrayCast(obj, type)
                    }
                else ->
                    throw ArrayIndexOutOfBoundsException(1)
            }

            return retVal
        }

        @Throws(Throwable::class)
        fun findHandleWithArgsCasting(parsedArgs: Array<Any?>): Int {
            for (j in handleDescs!!.indices) {
                var possible = false
                val mtypes = Type.getArgumentTypes(handleDescs!![j])
                if (mtypes.size != parsedArgs.size) continue

                for (i in mtypes.indices) {
                    val newValue = castObjectToType(parsedArgs[i]!!, mtypes[i])

                    if (newValue != null) {
                        possible = true
                        parsedArgs[i] = newValue
                    }
                    else {
                        possible = false
                        break
                    }
                }
                if (possible) {
                    return j
                }
            }
            return -1
        }

        @Throws(Throwable::class)
        fun fallback(intc: Any?, incf: Any?, incsd: Any?, args: Array<Any?>): Any? {
            tc = intc as ThreadContext
            val cf = incf as CallFrame?
            val csd = incsd as CallSiteDescriptor?
            val parsedArgs = parseArgArray(args)

            Ops.debugnoop(args[0] as SixModelObject?, intc)

            /* debug
            for(int i = 0; i < parsedArgs.length; ++i ) {
                System.out.println("parsed arg " + i + " as " + parsedArgs[i].getClass());
            }
            // */

            if (forCtors) {
                this.handleList = Class.forName(Type.getObjectType(declaringClass!!.replace('/', '.')).internalName,
                    false, tc!!.gc.byteClassLoader).constructors
            }

            // first, check for a cached handle, only recheck if it doesn't match
            if (handlePos == -1 || handleDescs != null && !argsMatch(handleDescs!![handlePos]!!, parsedArgs)) {
                handlePos = -1
                handlePos = findHandle(parsedArgs)
            }
            // we should have a handle now, unless we have to cast arguments around
            if (handlePos == -1) {
                handlePos = findHandleWithArgsCasting(parsedArgs)
            }
            // that should have worked, if not there's nothing we can dispatch to
            if (handlePos == -1) {
                failDispatch(parsedArgs)
            }

            /* debug
            if(forCtors) {
                System.out.println("ctor cand: " + ((Constructor) this.handleList[handlePos]).toGenericString());
            } else {
                System.out.println("mhand cand: " + (MethodHandle) this.handleList[handlePos]);
            }
            // */

            val rfh: MethodHandle
            try {
                rfh = MethodHandles.lookup().findStatic(RakudoJavaInterop::class.java, "filterReturnValueMethod",
                    MethodType.fromMethodDescriptorString(
                        "(Ljava/lang/Object;Lorg/raku/nqp/runtime/ThreadContext;)Ljava/lang/Object;",
                        tc!!.gc.byteClassLoader))
            } catch (nsme: ReflectiveOperationException) {
                /* Java multi-caught NoSuchMethodException|IllegalAccessException;
                 * their least common ancestor with no other subtypes in play. */
                throw ExceptionHandling.dieInternal(tc!!,
                    "Couldn't find the method for filtering return values from Java.")
            }

            val out: Any?
            if (forCtors) {
                val instance = (handleList!![handlePos] as Constructor<*>).newInstance(*parsedArgs)
                out = rfh.invoke(instance, tc)
            }
            else {
                val retVal = (handleList!![handlePos] as MethodHandle).invokeWithArguments(*parsedArgs)
                out = rfh.invoke(retVal, tc)
            }

            return out
        }
    }

    companion object {
        /**
         * Helper for not having to write recursive bytecode generation.
         * Public because of runtime visibility: the emitted adaptor bytecode
         * invokestatics org/raku/rakudo/RakudoJavaInterop.marshalOutRecursive
         * by name and descriptor.
         */
        @JvmStatic
        @Throws(Throwable::class)
        fun marshalOutRecursive(`in`: SixModelObject, tc: ThreadContext, what: Class<*>?): Any? {
            var out: Any? = null
            val gcx = RakOps.key.getGC(tc)
            var size = 0L
            if (Ops.islist(`in`, tc) == 1L) {
                return BootJavaInterop.marshalOutRecursive(`in`, tc, what)
            }
            else if (Ops.istype(`in`, gcx.List, tc) == 1L) {
                val p6list = Ops.decont(`in`, tc)
                val methElems = Ops.findmethod(p6list, "elems", tc)
                Ops.invokeDirect(tc, methElems, Ops.invocantCallSite, arrayOf<Any?>(p6list))
                try {
                    size = Ops.result_i(tc.curFrame!!)
                }
                catch (t: Throwable) {
                    ExceptionHandling.dieInternal(tc, "Cannot marshal a lazy list to Java")
                }

                // TODO get half the work of parseSingleArg() abstracted out of there
                //      i.e. the type mapping between Java and Rakudo, so we
                //      can actually do something with the "of" and thus
                //      can dispatch to e.g. int[] instead of just Object[]
                val methOf = Ops.findmethod(p6list, "of", tc)
                Ops.invokeDirect(tc, methOf, Ops.invocantCallSite, arrayOf<Any?>(p6list))
                val ofType = Ops.result_o(tc.curFrame!!)
                val methAtPos = Ops.findmethod(p6list, "AT-POS", tc)

                for (i in 0 until size) {
                    Ops.invokeDirect(tc, methAtPos,
                        Ops.storeCallSite,
                        arrayOf<Any?>(p6list, Ops.box_i(i, gcx.Int, tc)))
                    val cur: Any? = Ops.result_o(tc.curFrame!!)
                    var value: Any? = null
                    if (Ops.islist(cur as SixModelObject?, tc) == 1L) {
                        /* NOTE: preserved from the Java original: `out` may
                         * still be null here (NPE), and it marshals `in`
                         * rather than `cur`. */
                        (out as Array<Any?>)[i.toInt()] = BootJavaInterop.marshalOutRecursive(`in`, tc, what)
                    }
                    else if (Ops.istype(cur, gcx.List, tc) == 1L) {
                        value = marshalOutRecursive(cur!!, tc, what)
                    }
                    else {
                        value = parseSingleArg(cur, tc)
                    }
                    if (out == null) {
                        out = JArray.newInstance(Any::class.java, size.toInt())
                    }
                    JArray.set(out, i.toInt(), value)
                }
                if (java.util.List::class.java.isAssignableFrom(what)) {
                    out = Arrays.asList(*(out as Array<Any?>))
                }
            }
            else if (Ops.istype(`in`, gcx.Hash, tc) == 1L) {
                val p6hash = Ops.decont(`in`, tc)
                val methElems = Ops.findmethod(p6hash, "elems", tc)
                Ops.invokeDirect(tc, methElems, Ops.invocantCallSite, arrayOf<Any?>(p6hash))
                try {
                    size = Ops.result_i(tc.curFrame!!)
                }
                catch (t: Throwable) {
                    ExceptionHandling.dieInternal(tc, "Cannot marshal a lazy hash to Java")
                }
                val methKeys = Ops.findmethod(p6hash, "keys", tc)
                Ops.invokeDirect(tc, methKeys, Ops.invocantCallSite, arrayOf<Any?>(p6hash))
                val p6keyList = Ops.result_o(tc.curFrame!!)
                val methAtPos = Ops.findmethod(p6keyList, "AT-POS", tc)
                val methAtKey = Ops.findmethod(p6hash, "AT-KEY", tc)

                val outMap = HashMap<String?, Any?>()
                out = outMap
                for (i in 0 until size) {
                    Ops.invokeDirect(tc, methAtPos, Ops.storeCallSite, arrayOf<Any?>(p6keyList, Ops.box_i(i, gcx.Int, tc)))
                    val p6key = Ops.result_o(tc.curFrame!!)
                    Ops.invokeDirect(tc, methAtKey, Ops.storeCallSite, arrayOf<Any?>(p6hash, p6key))
                    val cur: Any? = Ops.result_o(tc.curFrame!!)
                    val value: Any?
                    if (Ops.islist(cur as SixModelObject?, tc) == 1L) {
                        /* NOTE: marshals `in` rather than `cur`, as in the
                         * Java original. */
                        value = BootJavaInterop.marshalOutRecursive(`in`, tc, what)
                    }
                    else if (Ops.istype(cur, gcx.List, tc) == 1L) {
                        value = marshalOutRecursive(cur!!, tc, what)
                    }
                    else {
                        value = parseSingleArg(cur, tc)
                    }
                    outMap.put(Ops.unbox_s(p6key, tc), value)
                }
            }
            // TODO associative types, which could for starters default to Map<Object> similar
            //      to how Positionals currently do, but we will want "of" checking there too
            return out
        }

        @JvmStatic
        fun parseSingleArg(inArg: SixModelObject?, tc: ThreadContext): Any? {
            var outArg: Any? = null
            // there doesn't seem to be an actual type Bool in gc or gcx
            if (!Ops.typeName(inArg, tc)!!.equals("Bool")) {
                // one decont for native types...
                val outerSS = Ops.decont(inArg, tc)!!
                    .st.REPR.get_storage_spec(tc, inArg!!.st)
                // ...and two for boxeds
                val innerSS = Ops.decont(Ops.decont(inArg, tc), tc)!!
                    .st.REPR.get_storage_spec(tc, Ops.decont(inArg, tc)!!.st)
                if (Boxable.NUM in outerSS.canBox) {
                    outArg = Ops.unbox_n(inArg, tc)
                }
                else if (Boxable.STR in outerSS.canBox) {
                    outArg = Ops.unbox_s(inArg, tc)
                }
                else if (Boxable.INT in outerSS.canBox) {
                    outArg = Ops.unbox_i(inArg, tc)
                }
                else if (Boxable.NUM in innerSS.canBox) {
                    outArg = Ops.unbox_n(inArg, tc)
                }
                else if (Boxable.STR in innerSS.canBox) {
                    outArg = Ops.unbox_s(inArg, tc)
                }
                else if (Boxable.INT in innerSS.canBox) {
                    outArg = Ops.unbox_i(inArg, tc)
                }
                else {
                    try {
                        outArg = RuntimeSupport.unboxJava(Ops.decont(inArg, tc))
                    } catch (e: Exception) {
                        throw ExceptionHandling.dieInternal(tc,
                            "Couldn't parse arguments in Java call. (Did you pass a type object?)")
                    }
                }
            }
            else {
                if (Ops.istrue(inArg, tc) == 1L) {
                    outArg = true
                }
                else if (Ops.isfalse(inArg, tc) == 1L) {
                    outArg = false
                }
            }
            return outArg
        }

        /* Resolved at runtime by name and hardcoded descriptor string
         * (see the findStatic in DispatchCallSite.fallback). */
        @JvmStatic
        fun filterReturnValueMethod(`in`: Any?, tc: ThreadContext): Any? {
            val gcx = RakOps.key.getGC(tc)
            if (`in` == null) {
                return gcx.Nil
            }

            val what: Class<*> = `in`.javaClass
            var out: Any?
            if (what == Void.TYPE) {
                out = null
            }
            else if (what == Integer.TYPE || what == java.lang.Integer::class.java) {
                out = (`in` as Int).toLong()
            }
            else if (what == java.lang.Short.TYPE || what == java.lang.Short::class.java) {
                out = (`in` as Short).toLong()
            } else if (what == java.lang.Byte.TYPE || what == java.lang.Byte::class.java) {
                out = (`in` as Byte).toLong()
            } else if (what == java.lang.Boolean.TYPE || what == java.lang.Boolean::class.java) {
                out = if (`in` as Boolean) gcx.True else gcx.False
            }
            else if (what == java.lang.Long.TYPE || what == java.lang.Double.TYPE || what == String::class.java || what == SixModelObject::class.java || what == java.lang.Long::class.java || what == java.lang.Double::class.java) {
                out = `in`
            }
            else if (what == java.lang.Float.TYPE || what == java.lang.Float::class.java) {
                out = (`in` as Float).toDouble()
            }
            else if (what == Character.TYPE || what == Character::class.java) {
                out = (`in` as Char).toString()
            }
            else {
                var stable: STable? = null
                if (gcx.rakudoInterop!!.commonSTable != null) {
                    stable = gcx.rakudoInterop!!.commonSTable
                }
                if (what.isArray) {
                    val ARRAY = tc.gc.BOOTArray!!
                    out = ARRAY.st.REPR.allocate(tc, ARRAY.st)
                    if (stable == null) {
                        stable = ARRAY.st
                    }
                    if (what.componentType.isPrimitive) {
                        /* NOTE: the (int[]) casts below are preserved from the
                         * Java original — they ClassCastException at runtime
                         * for long[]/short[]/byte[]/boolean[] (and the num
                         * branch's (double[]) for float[]). */
                        if (what.componentType == java.lang.Long.TYPE
                        || what.componentType == Integer.TYPE
                        || what.componentType == java.lang.Short.TYPE
                        || what.componentType == java.lang.Byte.TYPE
                        || what.componentType == java.lang.Boolean.TYPE) {
                            for (i in 0 until (`in` as IntArray).size) {
                                val cur = RakOps.p6box_i(`in`[i].toLong(), tc)
                                Ops.bindpos(out, i.toLong(), cur, tc)
                            }
                        }
                        else if (what.componentType == String::class.java
                        || what.componentType == Character.TYPE) {
                            for (i in 0 until (`in` as IntArray).size) {
                                @Suppress("UNCHECKED_CAST")
                                val cur = RakOps.p6box_s((`in` as Array<String?>)[i], tc)
                                Ops.bindpos(out, i.toLong(), cur, tc)
                            }
                        }
                        else if (what.componentType == java.lang.Float.TYPE
                        || what.componentType == java.lang.Double.TYPE) {
                            for (i in 0 until (`in` as IntArray).size) {
                                val cur = RakOps.p6box_n((`in` as DoubleArray)[i], tc)
                                Ops.bindpos(out, i.toLong(), cur, tc)
                            }
                        }
                    }
                    else {
                        for (i in 0 until (`in` as Array<*>).size) {
                            // need to special-case String.class here
                            val cur: SixModelObject
                            if (what.componentType == String::class.java) {
                                @Suppress("UNCHECKED_CAST")
                                cur = RakOps.p6box_s((`in` as Array<String?>)[i], tc)
                            }
                            else {
                                cur = RuntimeSupport.boxJava(`in`[i],
                                        gcx.rakudoInterop!!.getSTableForClass(what.componentType))
                            }
                            Ops.bindpos(out, i.toLong(), cur, tc)
                        }
                    }
                    val outList = Ops.create(gcx.List, tc)
                    val iterbuffer = Ops.create(gcx.IterationBuffer, tc)
                    Ops.bindattr(outList, gcx.List, "\$!reified", iterbuffer, tc)
                    val elems = Ops.elems(out, tc)
                    for (i in 0 until elems) {
                        Ops.bindpos(iterbuffer, i, Ops.atpos(out, i, tc), tc)
                    }
                    out = outList
                }
                else {
                    out = RuntimeSupport.boxJava(`in`, gcx.rakudoInterop!!.getSTableForClass(what))
                }
            }

            if (what == String::class.java || what == Character.TYPE || what == Character::class.java)
                Ops.return_s(out as String?, tc.curFrame!!)
            else if (what == java.lang.Float.TYPE || what == java.lang.Double.TYPE || what == java.lang.Double::class.java || what == java.lang.Float::class.java)
                Ops.return_n(out as Double, tc.curFrame!!)
            else if (what != Void.TYPE && (what.isPrimitive || what == java.lang.Long::class.java
                  || what == java.lang.Integer::class.java || what == java.lang.Short::class.java || what == java.lang.Byte::class.java))
                Ops.return_i(out as Long, tc.curFrame!!)
            else
                Ops.return_o(out as SixModelObject?, tc.curFrame!!)

            // the conditional is rather sketchy, but seems to be needed to
            // correctly return a new instance when we're called from
            // ConstructorDispatchCallSite, probably because of
            // Raku' .new creating a new CallFrame or something..?
            return if (Ops.result_o(tc.curFrame!!) != null) Ops.result_o(tc.curFrame!!) else Ops.result_o(tc.curFrame!!.caller!!)
        }

        /* Bound as an invokedynamic bootstrap Handle by name and descriptor
         * from the emitted adaptor bytecode. */
        @JvmStatic
        fun multiBootstrap(lookup: MethodHandles.Lookup, name: String, type: MethodType, vararg hlist: Any?): CallSite {
            val cs = DispatchCallSite(name, type, hlist)
            cs.setTarget(cs.fallback)
            return cs
        }

        /* Bound as an invokedynamic bootstrap Handle by name and descriptor
         * from the emitted adaptor bytecode. */
        @JvmStatic
        fun constructorBootstrap(lookup: MethodHandles.Lookup, name: String, type: MethodType, declClass: String): CallSite {
            val cs = DispatchCallSite(name, type, declClass)
            cs.setTarget(cs.fallback)
            return cs
        }
    }

    override fun marshalOut(c: MethodContext, what: Class<*>, ix: Int) {
        val mv = c.mv!!

        if (what.componentType != null
            || java.util.List::class.java.isAssignableFrom(what)
            || java.util.Map::class.java.isAssignableFrom(what)) {
            emitGetFromNQP(c, ix, storageForType(what))
            mv.visitVarInsn(Opcodes.ALOAD, c.tcLoc)
            mv.visitLdcInsn(Type.getType(what))
            mv.visitMethodInsn(Opcodes.INVOKESTATIC, "org/raku/rakudo/RakudoJavaInterop", "marshalOutRecursive",
                Type.getMethodDescriptor(Type.getType(Object::class.java), TYPE_SMO, TYPE_TC, Type.getType(Class::class.java)))
        }

        else {
            super.marshalOut(c, what, ix)
        }
    }

    protected open fun startVarArityCallout(cc: ClassContext, desc: String): MethodContext {
        val mc = MethodContext()
        mc.cc = cc
        val mv = cc.cv!!.visitMethod(Opcodes.ACC_PUBLIC or Opcodes.ACC_STATIC, "qb_" + (cc.nextCallout++),
                Type.getMethodDescriptor(Type.VOID_TYPE, TYPE_CU, TYPE_TC, TYPE_CR, TYPE_CSD, TYPE_AOBJ),
                null, null)
        mc.mv = mv
        val av = mv.visitAnnotation("Lorg/raku/nqp/runtime/CodeRefAnnotation;", true)
        av.visit("name", "callout " + cc.target!!.name + " " + desc)
        av.visitEnd()
        mv.visitCode()
        cc.descriptors.add(desc)

        mc.argsLoc = 4
        mc.csdLoc = 3
        mc.cfLoc = 5
        mc.tcLoc = 1

        mv.visitTypeInsn(Opcodes.NEW, "org/raku/nqp/runtime/CallFrame")
        mv.visitInsn(Opcodes.DUP)
        mv.visitVarInsn(Opcodes.ALOAD, 1) // tc
        mv.visitVarInsn(Opcodes.ALOAD, 2) // cr
        mv.visitMethodInsn(Opcodes.INVOKESPECIAL, "org/raku/nqp/runtime/CallFrame", "<init>", Type.getMethodDescriptor(Type.VOID_TYPE, TYPE_TC, TYPE_CR))
        mv.visitVarInsn(Opcodes.ASTORE, 5) // cf;

        mc.tryStart = org.objectweb.asm.Label()
        mv.visitLabel(mc.tryStart)

        mv.visitVarInsn(Opcodes.ALOAD, 5) // cf
        mv.visitVarInsn(Opcodes.ALOAD, 3) // csd
        mv.visitVarInsn(Opcodes.ALOAD, 4) // args
        emitInteger(mc, 1)
        emitInteger(mc, -1)
        mv.visitMethodInsn(Opcodes.INVOKESTATIC, TYPE_OPS.internalName, "checkarity", Type.getMethodDescriptor(TYPE_CSD, TYPE_CF, TYPE_CSD, TYPE_AOBJ, Type.INT_TYPE, Type.INT_TYPE))
        mv.visitVarInsn(Opcodes.ASTORE, 3) // csd
        mv.visitVarInsn(Opcodes.ALOAD, 1) // tc
        mv.visitFieldInsn(Opcodes.GETFIELD, TYPE_TC.internalName, "flatArgs", TYPE_AOBJ.descriptor)
        mv.visitVarInsn(Opcodes.ASTORE, 4) // args

        return mc
    }

    protected open fun createAdaptorMultiDispatch(cc: ClassContext, mlist: ArrayList<Method>) {
        val name = "mmd+" + mlist[0].name
        val desc = "method/" + name + "/([Ljava/lang/Object;)Ljava/lang/Object;"

        val mc = startVarArityCallout(cc, desc)

        // what if this is the only static one?
        if (!Modifier.isStatic(mlist[0].modifiers)) marshalOut(mc, mlist[0].declaringClass, 0)
        val disphandle = Handle(Opcodes.H_INVOKESTATIC, "org/raku/rakudo/RakudoJavaInterop", "multiBootstrap",
                "(Ljava/lang/invoke/MethodHandles\$Lookup;Ljava/lang/String;Ljava/lang/invoke/MethodType;[Ljava/lang/Object;)" +
                "Ljava/lang/invoke/CallSite;")
        val candhandles = arrayOfNulls<Handle>(mlist.size)
        var i = 0
        for (next in mlist) {
            candhandles[i++] = Handle(
                    if (Modifier.isStatic(next.modifiers)) Opcodes.H_INVOKESTATIC else Opcodes.H_INVOKEVIRTUAL,
                    next.declaringClass.name.replace('.', '/'),
                    next.name,
                    Type.getMethodDescriptor(next))
        }

        mc.mv!!.visitVarInsn(Opcodes.ALOAD, 1)
        mc.mv!!.visitVarInsn(Opcodes.ALOAD, 5)
        mc.mv!!.visitVarInsn(Opcodes.ALOAD, 3)
        mc.mv!!.visitVarInsn(Opcodes.ALOAD, 4)
        @Suppress("UNCHECKED_CAST")
        mc.mv!!.visitInvokeDynamicInsn(mlist[0].name,
                "(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/Object;[Ljava/lang/Object;)Ljava/lang/Object;",
                disphandle, *(candhandles as Array<Any>))

        endCallout(mc)
    }

    override fun computeHOW(tc: ThreadContext, name: String): SixModelObject? {
        val gcx = RakOps.key.getGC(tc)
        val mo = gcx.JavaHOW!!.st.REPR.allocate(tc, gcx.JavaHOW!!.st)
        mo.bind_attribute_boxed(tc, gcx.JavaHOW, "\$!name", STable.NO_HINT,
            RakOps.p6box_s(name, tc))

        return mo
    }

    protected open fun createConstructorDispatchAdaptor(cc: ClassContext, ks: Array<Constructor<*>>) {
        val desc = "method/mmd+new/([Ljava/lang/Object;)L" + ks[0].declaringClass.name.replace('.', '/') + ";"
        val className = Type.getInternalName(ks[0].declaringClass)
        val mc = startVarArityCallout(cc, desc)

        val disphandle = Handle(Opcodes.H_INVOKESTATIC, "org/raku/rakudo/RakudoJavaInterop", "constructorBootstrap",
                "(Ljava/lang/invoke/MethodHandles\$Lookup;Ljava/lang/String;Ljava/lang/invoke/MethodType;Ljava/lang/String;)" +
                "Ljava/lang/invoke/CallSite;")

        preMarshalIn(mc, ks[0].declaringClass, 0)

        mc.mv!!.visitVarInsn(Opcodes.ALOAD, 1)
        mc.mv!!.visitVarInsn(Opcodes.ALOAD, 5)
        mc.mv!!.visitVarInsn(Opcodes.ALOAD, 3)
        mc.mv!!.visitVarInsn(Opcodes.ALOAD, 4)
        mc.mv!!.visitInvokeDynamicInsn("new",
                "(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/Object;[Ljava/lang/Object;)Ljava/lang/Object;",
                disphandle, className)

        endCallout(mc)
    }

    override fun createAdaptor(target: Class<*>): ClassContext {
        val cw = ClassWriter(ClassWriter.COMPUTE_MAXS or ClassWriter.COMPUTE_FRAMES)
        val className = "org/raku/nqp/generatedadaptor/" + target.name.replace('.', '/')
        cw.visit(Opcodes.V1_7, Opcodes.ACC_PUBLIC or Opcodes.ACC_SUPER, className, null, TYPE_CU.internalName, null)

        cw.visitField(Opcodes.ACC_STATIC or Opcodes.ACC_PUBLIC, "constants", "[Ljava/lang/Object;", null, null).visitEnd()

        val cc = ClassContext()
        cc.cv = cw
        cc.className = className
        cc.target = target

        val multiDescs = HashMap<String, Int>()
        for (m in target.methods) {
            if (multiDescs.containsKey(m.name)) {
                multiDescs[m.name] = multiDescs[m.name]!! + 1
            }
            else {
                multiDescs[m.name] = 1
            }
        }
        val multiMethods = HashMap<String, ArrayList<Method>>()
        for (m in target.methods) {
            if (m.isSynthetic) {
                // synthetics don't get their own perl6-level method, because
                // they only exist as a visibility aid for the class we're
                // generating an adaptor for
                continue
            }
            if (multiDescs[m.name]!! > 1) {
                if (multiMethods[m.name] == null) {
                    multiMethods[m.name] = ArrayList()
                }
                multiMethods[m.name]!!.add(m)
            }
            createAdaptorMethod(cc, m)
        }
        for (entry in multiMethods.entries) {
            createAdaptorMultiDispatch(cc, entry.value)
        }
        for (f in target.fields) {
            if (f.isSynthetic)
                continue
            createAdaptorField(cc, f)
        }
        for (c in target.constructors) {
            if (c.isSynthetic)
                continue
            createAdaptorConstructor(cc, c)
        }
        // what we actually want to do is grab all the methods we generated in
        // the for() directly above and generate a varargs shortname
        // &new()-equivalent, which dispatches among the generated
        // adaptorConstructors - which aren't really constructors but static
        // methods
        if (target.constructors.isNotEmpty())
            createConstructorDispatchAdaptor(cc, target.constructors)
        createAdaptorSpecials(cc)
        compunitMethods(cc)

        finishClass(cc)
        /* debug
        try {
            java.nio.file.Files.write(new java.io.File(className.replace('/','_') + ".class").toPath(), cc.cv.toByteArray());
        } catch (java.io.IOException e) {
            e.printStackTrace();
        }
        // */

        return cc
    }

    fun addToClassPath(path: String) {
        var thePath = "file:" + path
        if (!thePath.endsWith("jar") && !thePath.endsWith("class"))
            thePath = "$thePath/"

        try {
            // ...but here's what we actually do:
            /* NOTE: reflective URLClassLoader.addURL — JDK-9+-fragile, but
             * preserved as-is. */
            val methAddURL = URLClassLoader::class.java.getDeclaredMethod("addURL", URL::class.java)
            methAddURL.setAccessible(true)
            methAddURL.invoke(javaClass.classLoader, URL(thePath))
        }
        catch (nsme: NoSuchMethodException) {
            throw ExceptionHandling.dieInternal(gc.getCurrentThreadContext()!!, nsme)
        }
        catch (ite: InvocationTargetException) {
            throw ExceptionHandling.dieInternal(gc.getCurrentThreadContext()!!, ite)
        }
        catch (iae: IllegalAccessException) {
            throw ExceptionHandling.dieInternal(gc.getCurrentThreadContext()!!, iae)
        }
        catch (mue: MalformedURLException) {
            throw ExceptionHandling.dieInternal(gc.getCurrentThreadContext()!!, mue)
        }
    }

    override fun computeInterop(tc: ThreadContext, klass: Class<*>): SixModelObject {
        val adaptor = createAdaptor(klass)

        val adaptorUnit: CompilationUnit
        try {
            @Suppress("DEPRECATION")
            adaptorUnit = adaptor.constructed!!.newInstance() as CompilationUnit
        } catch (roe: ReflectiveOperationException) {
            throw RuntimeException(roe)
        }
        adaptorUnit.initializeCompilationUnit(tc)

        val hash = gc.BOOTHash!!.st.REPR.allocate(tc, gc.BOOTHash!!.st)

        val methodOrder = gc.BOOTArray!!.st.REPR.allocate(tc, gc.BOOTArray!!.st)
        val methods = gc.BOOTHash!!.st.REPR.allocate(tc, gc.BOOTHash!!.st)
        val submethods = gc.BOOTHash!!.st.REPR.allocate(tc, gc.BOOTHash!!.st)

        val names = HashMap<String, SixModelObject?>()

        val gcx = RakOps.key.getGC(tc)
        val protoSt = gcx.JavaHOW!!.st
        val ThisHOW = computeHOW(tc, klass.name)!!
        val freshType = protoSt.REPR.type_object_for(tc, ThisHOW)

        val mult = HashMap<String, SixModelObject?>()
        for (i in 0 until adaptor.descriptors.size) {
            val desc = adaptor.descriptors[i]
            val cr = adaptorUnit.lookupCodeRef(i)

            val s1 = desc.indexOf('/')
            val s2 = desc.indexOf('/', s1 + 1)

            // dispatch methods *should* be last, but this might be a
            // spot to check if things start breaking...
            val shorten = desc.substring(s1 + 1, s2)
            if (shorten.contains("mmd+")) {
                val shortmult = shorten.substring(shorten.indexOf("+") + 1)
                mult[shortmult] = cr
                // don't add multi candidates with mmd+ prefix
                continue
            }
            if (names.containsKey(shorten)) {
                names[shorten] = null
            }
            else {
                // there's probably a better way to do this
                if (shorten == "toString") {
                    if (!names.containsKey("Str")) names["Str"] = cr
                    if (!names.containsKey("gist")) names["gist"] = cr
                }
                names[shorten] = cr
            }
            names[desc] = cr
        }

        for (ent in mult.entries) {
            names[ent.key] = ent.value
        }

        var pos = 0L
        val it = names.entries.iterator()
        while (it.hasNext()) {
            val ent = it.next()
            if (ent.value != null) {
                methodOrder.bind_pos_boxed(tc, pos++, ent.value)
                methods.bind_key_boxed(tc, ent.key, ent.value)
                hash.bind_key_boxed(tc, ent.key, ent.value)
            }
            else
                it.remove()
        }

        freshType.st.MethodCache = names
        freshType.st.ModeFlags = freshType.st.ModeFlags or STable.METHOD_CACHE_AUTHORITATIVE

        ThisHOW.bind_attribute_boxed(tc, gcx.JavaHOW, "%!submethods", STable.NO_HINT, submethods)
        ThisHOW.bind_attribute_boxed(tc, gcx.JavaHOW, "%!methods", STable.NO_HINT, Ops.hllizefor(methods, "Raku", tc))
        ThisHOW.bind_attribute_boxed(tc, gcx.JavaHOW, "@!method_order", STable.NO_HINT, methodOrder)

        hash.bind_key_boxed(tc, "/TYPE/", freshType)

        return hash
    }
}
