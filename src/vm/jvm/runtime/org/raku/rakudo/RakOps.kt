package org.raku.rakudo

import java.util.ArrayList

import org.raku.nqp.runtime.BootJavaInterop
import org.raku.nqp.runtime.CallFrame
import org.raku.nqp.runtime.CallSiteDescriptor
import org.raku.nqp.runtime.CodeRef
import org.raku.nqp.runtime.ContextKey
import org.raku.nqp.runtime.ExceptionHandling
import org.raku.nqp.runtime.Ops
import org.raku.nqp.runtime.StaticCodeInfo
import org.raku.nqp.runtime.ThreadContext
import org.raku.nqp.sixmodel.ContainerSpec
import org.raku.nqp.sixmodel.Inlining
import org.raku.nqp.sixmodel.STable
import org.raku.nqp.sixmodel.SixModelObject
import org.raku.nqp.sixmodel.TypeObject
import org.raku.nqp.sixmodel.reprs.CallCaptureInstance
import org.raku.nqp.sixmodel.reprs.ContextRefInstance

/**
 * Contains implementation of nqp:: ops specific to Rakudo
 */
object RakOps {
    const val DEBUG_MODE = false

    class ThreadExt(tc: ThreadContext) {
        @JvmField var firstPhaserCodeBlock: SixModelObject? = null
        @JvmField var prePhaserFrames = ArrayList<CallFrame>()
    }

    class GlobalExt(tc: ThreadContext) {
        @JvmField var Mu: SixModelObject? = null
        @JvmField var Any: SixModelObject? = null
        @JvmField var Code: SixModelObject? = null
        @JvmField var Routine: SixModelObject? = null
        @JvmField var Signature: SixModelObject? = null
        @JvmField var Parameter: SixModelObject? = null
        @JvmField var Int: SixModelObject? = null
        @JvmField var Num: SixModelObject? = null
        @JvmField var Str: SixModelObject? = null
        @JvmField var List: SixModelObject? = null
        @JvmField var IterationBuffer: SixModelObject? = null
        @JvmField var Iterable: SixModelObject? = null
        @JvmField var Array: SixModelObject? = null
        @JvmField var Nil: SixModelObject? = null
        @JvmField var Map: SixModelObject? = null
        @JvmField var Hash: SixModelObject? = null
        @JvmField var Junction: SixModelObject? = null
        @JvmField var Scalar: SixModelObject? = null
        @JvmField var Capture: SixModelObject? = null
        @JvmField var ContainerDescriptor: SixModelObject? = null
        @JvmField var False: SixModelObject? = null
        @JvmField var True: SixModelObject? = null
        @JvmField var AutoThreader: SixModelObject? = null
        @JvmField var Positional: SixModelObject? = null
        @JvmField var PositionalBindFailover: SixModelObject? = null
        @JvmField var Associative: SixModelObject? = null
        @JvmField var EMPTYARR: SixModelObject? = null
        @JvmField var EMPTYHASH: SixModelObject? = null
        @JvmField var rakudoInterop: RakudoJavaInterop? = null
        @JvmField var JavaHOW: SixModelObject? = null
        /* Package-private in the Java original; Kotlin has no package
         * visibility, so this widens to a public field (the AttrInfo
         * precedent). */
        @JvmField var initialized = false
    }

    @JvmField val key = ContextKey(ThreadExt::class.java, GlobalExt::class.java)

    /* Parameter hints for fast lookups. */
    private const val HINT_CODE_DO = 0L
    private const val HINT_CODE_SIG = 1L
    private const val HINT_ROUTINE_RW = 8L
    private const val HINT_SIG_PARAMS = 0L
    private const val HINT_SIG_RETURNS = 1L
    private const val HINT_SIG_CODE = 4L
    const val HINT_CD_OF = 0
    const val HINT_CD_NAME = 1
    const val HINT_CD_DEFAULT = 2

    @JvmStatic
    fun p6init(tc: ThreadContext): SixModelObject? {
        val gcx = key.getGC(tc)
        if (!gcx.initialized) {
            tc.gc.contConfigs.put("value_desc_cont", RakudoContainerConfigurer())
            val BOOTArray = tc.gc.BOOTArray!!
            gcx.EMPTYARR = BOOTArray.st.REPR.allocate(tc, BOOTArray.st)
            val BOOTHash = tc.gc.BOOTHash!!
            gcx.EMPTYHASH = BOOTHash.st.REPR.allocate(tc, BOOTHash.st)
            gcx.rakudoInterop = RakudoJavaInterop(tc.gc)
            gcx.initialized = true
        }
        return null
    }

    @JvmStatic
    fun p6setitertype(type: SixModelObject?, tc: ThreadContext): SixModelObject? {
        val gcx = key.getGC(tc)
        gcx.Iterable = type
        return type
    }

    @JvmStatic
    fun p6setassociativetype(type: SixModelObject?, tc: ThreadContext): SixModelObject? {
        val gcx = key.getGC(tc)
        gcx.Associative = type
        return type
    }

    @JvmStatic
    fun p6setiterbuftype(type: SixModelObject?, tc: ThreadContext): SixModelObject? {
        val gcx = key.getGC(tc)
        gcx.IterationBuffer = type
        return type
    }

    @JvmStatic
    fun p6settypes(conf: SixModelObject?, tc: ThreadContext): SixModelObject? {
        val gcx = key.getGC(tc)
        gcx.Mu = conf!!.at_key_boxed(tc, "Mu")
        gcx.Any = conf.at_key_boxed(tc, "Any")
        gcx.Code = conf.at_key_boxed(tc, "Code")
        gcx.Routine = conf.at_key_boxed(tc, "Routine")
        gcx.Signature = conf.at_key_boxed(tc, "Signature")
        gcx.Parameter = conf.at_key_boxed(tc, "Parameter")
        gcx.Int = conf.at_key_boxed(tc, "Int")
        gcx.Num = conf.at_key_boxed(tc, "Num")
        gcx.Str = conf.at_key_boxed(tc, "Str")
        gcx.List = conf.at_key_boxed(tc, "List")
        gcx.IterationBuffer = conf.at_key_boxed(tc, "IterationBuffer")
        gcx.Iterable = conf.at_key_boxed(tc, "Iterable")
        gcx.Array = conf.at_key_boxed(tc, "Array")
        gcx.Nil = conf.at_key_boxed(tc, "Nil")
        gcx.Map = conf.at_key_boxed(tc, "Map")
        gcx.Hash = conf.at_key_boxed(tc, "Hash")
        gcx.Junction = conf.at_key_boxed(tc, "Junction")
        gcx.Scalar = conf.at_key_boxed(tc, "Scalar")
        gcx.Capture = conf.at_key_boxed(tc, "Capture")
        gcx.ContainerDescriptor = conf.at_key_boxed(tc, "ContainerDescriptor")
        gcx.False = conf.at_key_boxed(tc, "False")
        gcx.True = conf.at_key_boxed(tc, "True")
        gcx.Associative = conf.at_key_boxed(tc, "Associative")
        gcx.JavaHOW = conf.at_key_boxed(tc, "Metamodel")!!.st.WHO!!.at_key_boxed(tc, "JavaHOW")
        return conf
    }

    @JvmStatic
    fun p6setautothreader(autoThreader: SixModelObject?, tc: ThreadContext): SixModelObject? {
        val gcx = key.getGC(tc)
        gcx.AutoThreader = autoThreader
        return autoThreader
    }

    @JvmStatic
    fun p6configposbindfailover(p: SixModelObject?, pbf: SixModelObject?, tc: ThreadContext): SixModelObject? {
        val gcx = key.getGC(tc)
        gcx.Positional = p
        gcx.PositionalBindFailover = pbf
        return p
    }

    @JvmStatic
    fun booleanize(x: Int, tc: ThreadContext): SixModelObject? {
        val gcx = key.getGC(tc)
        return if (x == 0) gcx.False else gcx.True
    }

    @JvmStatic
    fun p6definite(obj: SixModelObject?, tc: ThreadContext): SixModelObject? {
        val gcx = key.getGC(tc)
        return if (Ops.isnull(obj) == 1L || Ops.decont(obj, tc) is TypeObject) gcx.False else gcx.True
    }

    @JvmStatic
    fun p6box_i(value: Long, tc: ThreadContext): SixModelObject {
        val gcx = key.getGC(tc)
        val res = gcx.Int!!.st.REPR.allocate(tc, gcx.Int!!.st)
        res.set_int(tc, value)
        return res
    }

    @JvmStatic
    fun p6box_u(value: Long, tc: ThreadContext): SixModelObject {
        val gcx = key.getGC(tc)
        val res = gcx.Int!!.st.REPR.allocate(tc, gcx.Int!!.st)
        res.set_int(tc, value)
        return res
    }

    @JvmStatic
    fun p6box_n(value: Double, tc: ThreadContext): SixModelObject {
        val gcx = key.getGC(tc)
        val res = gcx.Num!!.st.REPR.allocate(tc, gcx.Num!!.st)
        res.set_num(tc, value)
        return res
    }

    @JvmStatic
    fun p6box_s(value: String?, tc: ThreadContext): SixModelObject {
        val gcx = key.getGC(tc)
        val res = gcx.Str!!.st.REPR.allocate(tc, gcx.Str!!.st)
        res.set_str(tc, value)
        return res
    }

    @JvmStatic
    fun p6argvmarray(tc: ThreadContext, csd: CallSiteDescriptor, args: Array<Any?>): SixModelObject {
        val BOOTArray = tc.gc.BOOTArray!!
        val res = BOOTArray.st.REPR.allocate(tc, BOOTArray.st)
        for (i in 0 until csd.numPositionals) {
            val toBind: SixModelObject?
            when (csd.argFlags[i]) {
                CallSiteDescriptor.ARG_INT ->
                    toBind = p6box_i(args[i] as Long, tc)
                CallSiteDescriptor.ARG_UINT ->
                    toBind = p6box_u(args[i] as Long, tc)
                CallSiteDescriptor.ARG_NUM ->
                    toBind = p6box_n(args[i] as Double, tc)
                CallSiteDescriptor.ARG_STR ->
                    toBind = p6box_s(args[i] as String?, tc)
                else ->
                    toBind = Ops.hllize(args[i] as SixModelObject?, tc)
            }
            res.bind_pos_boxed(tc, i.toLong(), toBind)
        }
        return res
    }

    @JvmStatic
    fun p6bindsig(tc: ThreadContext, csd: CallSiteDescriptor, args: Array<Any?>?): CallSiteDescriptor? {
        var theCsd = csd
        var theArgs = args
        /* Do any flattening before processing begins. */
        val cf = tc.curFrame!!
        if (theCsd.hasFlattening) {
            theCsd = theCsd.explodeFlattening(cf, theArgs!!)
            theArgs = tc.flatArgs
        }
        cf.csd = theCsd
        cf.args = theArgs

        /* Look up parameters to bind. */
        if (DEBUG_MODE) {
            if (cf.codeRef.name != null)
                System.err.println("Binding for " + cf.codeRef.name)
        }
        val gcx = key.getGC(tc)
        val sig = cf.codeRef.codeObject!!
            .get_attribute_boxed(tc, gcx.Code, "$!signature", HINT_CODE_SIG)
        val params = sig!!
            .get_attribute_boxed(tc, gcx.Signature, "@!params", HINT_SIG_PARAMS)

        /* Run binder, and handle any errors. */
        val error = arrayOfNulls<Any>(3)
        val bindResult = Binder.bind(tc, gcx, cf, params!!, theCsd, theArgs, false, error)
        if (bindResult == Binder.BIND_RESULT_FAIL || bindResult == Binder.BIND_RESULT_JUNCTION) {
            if (bindResult == Binder.BIND_RESULT_FAIL) {
                if (error[0] is String) {
                    throw ExceptionHandling.dieInternal(tc, error[0] as String)
                }
                else {
                    Ops.invokeDirect(tc, error[0] as SixModelObject?,
                        error[1] as CallSiteDescriptor, error[2] as Array<Any?>)
                }
                /* NOTE: no break in the Java original — a FAIL whose thrower
                 * invocation returns falls through into the junction
                 * auto-threading below. */
            }
            /* Invoke the auto-threader. */
            theCsd = theCsd.injectInvokee(tc, theArgs!!, cf.codeRef.codeObject)
            theArgs = tc.flatArgs
            Ops.invokeDirect(tc, gcx.AutoThreader, theCsd, theArgs!!)
            Ops.return_o(
                Ops.result_o(cf), cf)

            /* Return null to indicate immediate return to the routine. */
            return null
        }

        /* The binder may, for a variety of reasons, wind up calling Raku code and overwriting flatArgs, so it needs to be set at the end to return reliably */
        tc.flatArgs = theArgs
        return theCsd
    }

    /* Like p6bindsig, but reports whether binding worked instead of erroring,
     * for a frame whose bind failure the invoking dispatch will turn into a
     * resumption. Returns 1 on success and 0 on failure; a junction counts
     * as a failure, the same answer MoarVM's Binder.try_bind_sig gives. The
     * (possibly flattened) callsite and arguments are left on the frame and
     * in tc.flatArgs for the emitted code to reload its locals from. */
    @JvmStatic
    fun p6trybindsig(tc: ThreadContext, csd: CallSiteDescriptor, args: Array<Any?>?): Long {
        var theCsd = csd
        var theArgs = args
        val cf = tc.curFrame!!
        if (theCsd.hasFlattening) {
            theCsd = theCsd.explodeFlattening(cf, theArgs!!)
            theArgs = tc.flatArgs
        }
        cf.csd = theCsd
        cf.args = theArgs
        val gcx = key.getGC(tc)
        val sig = cf.codeRef.codeObject!!
            .get_attribute_boxed(tc, gcx.Code, "$!signature", HINT_CODE_SIG)
        val params = sig!!
            .get_attribute_boxed(tc, gcx.Signature, "@!params", HINT_SIG_PARAMS)
        val ok = Binder.bind(tc, gcx, cf, params!!, theCsd, theArgs, false, null) == Binder.BIND_RESULT_OK
        /* The binder can call code that overwrites flatArgs; restore it. */
        tc.flatArgs = theArgs
        return if (ok) 1 else 0
    }

    /**
     * Report why binding failed, for the HLL bind_error hook. A lowered
     * parameter's check has already failed and no dispatch wanted to resume
     * on it, so re-run the binder over the arguments the frame was entered
     * with to find out which parameter did not match and raise the language's
     * own error. The capture is an nqp one, straight off the failing frame,
     * so this cannot go through p6bindcaptosig -- that takes a Raku Capture.
     */
    @JvmStatic
    fun p6bindfailerror(cap: SixModelObject?, code: SixModelObject?, tc: ThreadContext): SixModelObject? {
        val capture = cap as? CallCaptureInstance
            ?: throw ExceptionHandling.dieInternal(tc, "p6bindfailerror needs a capture")
        val gcx = key.getGC(tc)
        val sig = code!!.get_attribute_boxed(tc, gcx.Code, "\$!signature", HINT_CODE_SIG)
        val params = sig!!.get_attribute_boxed(tc, gcx.Signature, "@!params", HINT_SIG_PARAMS)

        /* Bind into the frame that failed, not this one, so anything the
         * binder reports is phrased against it. */
        val frame = tc.curFrame!!.caller ?: tc.curFrame!!
        val error = arrayOfNulls<Any>(3)
        Binder.bind(tc, gcx, frame, params!!, capture.descriptor!!, capture.args, false, error)
        if (error[0] is String)
            throw ExceptionHandling.dieInternal(tc, error[0] as String)
        if (error[0] != null)
            Ops.invokeDirect(tc, error[0] as SixModelObject?,
                error[1] as CallSiteDescriptor, error[2] as Array<Any?>)
        /* The binder found nothing to complain about, so say what we know. */
        throw ExceptionHandling.dieInternal(tc, "Bind check failed")
    }

    @JvmStatic
    fun p6bindcaptosig(sig: SixModelObject?, cap: SixModelObject?, tc: ThreadContext): SixModelObject? {
        val cf = tc.curFrame!!

        val gcx = key.getGC(tc)
        val csd = Binder.explodeCapture(tc, gcx, cap)
        val params = sig!!.get_attribute_boxed(tc, gcx.Signature,
            "@!params", HINT_SIG_PARAMS)

        val error = arrayOfNulls<Any>(3)
        when (Binder.bind(tc, gcx, cf, params!!, csd, tc.flatArgs, false, error)) {
            Binder.BIND_RESULT_FAIL, Binder.BIND_RESULT_JUNCTION -> {
                if (error[0] is String) {
                    throw ExceptionHandling.dieInternal(tc, error[0] as String)
                }
                else {
                    Ops.invokeDirect(tc, error[0] as SixModelObject?,
                        error[1] as CallSiteDescriptor, error[2] as Array<Any?>)
                }
                /* NOTE: the Java original's cases fall through into
                 * `default: return sig` after a thrower invocation that
                 * returns. */
            }
        }
        return sig
    }

    @JvmStatic
    fun p6isbindable(sig: SixModelObject?, cap: SixModelObject?, tc: ThreadContext): Long {
        val gcx = key.getGC(tc)

        val csd: CallSiteDescriptor
        val args: Array<Any?>?
        if (cap is CallCaptureInstance) {
            csd = cap.descriptor!!
            args = cap.args
        } else {
            csd = Binder.explodeCapture(tc, gcx, cap)
            args = tc.flatArgs
        }

        val params = sig!!.get_attribute_boxed(tc, gcx.Signature,
            "@!params", HINT_SIG_PARAMS)
        val codeObj = sig.get_attribute_boxed(tc, gcx.Signature,
            "$!code", HINT_SIG_CODE)
        val cr = codeObj!!.get_attribute_boxed(tc, gcx.Code,
            "$!do", HINT_CODE_DO) as CodeRef

        val cf = CallFrame(tc, cr)
        try {
            return when (Binder.bind(tc, gcx, cf, params!!, csd, args, false, null)) {
                Binder.BIND_RESULT_FAIL -> 0L
                else -> 1L
            }
        }
        finally {
            tc.curFrame = tc.curFrame!!.caller
        }
    }

    private val STORE = CallSiteDescriptor(
        byteArrayOf(CallSiteDescriptor.ARG_OBJ, CallSiteDescriptor.ARG_OBJ), null)
    private val storeThrower = CallSiteDescriptor(
        byteArrayOf(CallSiteDescriptor.ARG_OBJ), null)

    /* Return-value decontainerization through the raku-rv-decont(-6c)
     * dispatcher, with the dispatch site cached per routine rather than per
     * bytecode instruction: an invokedynamic on every routine return is a
     * large slice of the per-class indy budget, which the core setting
     * overflows. */
    private val rvDecontSites =
        java.util.concurrent.ConcurrentHashMap<SixModelObject, org.raku.nqp.dispatch.DispatchCallSite>()

    /* The map's keys are routine objects, and a routine holds its whole
     * serialization-context graph. In a process that runs programs in turn --
     * the eval server -- entries from a finished run pin that run's entire
     * type universe, so the map must go cold with the dispatch caches. */
    init {
        org.raku.nqp.dispatch.DispatchBootstrap.registerResettable { rvDecontSites.clear() }
    }
    private val rvDecontSiteType = java.lang.invoke.MethodType.methodType(Void.TYPE)
    private val rvDecontCallSite = CallSiteDescriptor(
        byteArrayOf(CallSiteDescriptor.ARG_OBJ), null)

    @JvmStatic
    fun p6decontrv_rt(routine: SixModelObject?, value: SixModelObject?, sixc: Long,
                      tc: ThreadContext): SixModelObject? {
        val site = rvDecontSites.computeIfAbsent(routine!!) {
            org.raku.nqp.dispatch.DispatchCallSite(rvDecontSiteType)
        }
        org.raku.nqp.dispatch.Dispatch.dispatchWithDescriptor(site,
            if (sixc != 0L) "raku-rv-decont-6c" else "raku-rv-decont",
            rvDecontCallSite, tc, arrayOf<Any?>(value))
        return Ops.result_o(tc.curFrame!!)
    }

    @JvmStatic
    fun p6store(cont: SixModelObject?, value: SixModelObject?, tc: ThreadContext): SixModelObject? {
        val spec = cont!!.st.ContainerSpec
        if (spec != null) {
            spec.store(tc, cont, Ops.decont(value, tc)!!)
        }
        else {
            val meth = Ops.findmethodNonFatal(cont, "STORE", tc)
            if (Ops.isnull(meth) == 0L) {
                /* Through the dispatcher: STORE resolves to a multi's proto,
                 * and a raw invocation of its {*} would resume whatever
                 * unrelated dispatch is innermost. */
                Ops.invokeMethodViaDispatch(tc, meth,
                    STORE, arrayOf<Any?>(cont, value))
            }
            else {
                val thrower = getThrower(tc, "X::Assignment::RO")
                if (thrower == null)
                    ExceptionHandling.dieInternal(tc, "Cannot assign to a non-container")
                else
                    Ops.invokeDirect(tc, thrower,
                        storeThrower, arrayOf<Any?>(cont))
            }
        }
        return cont
    }

    private val genIns = CallSiteDescriptor(
        byteArrayOf(CallSiteDescriptor.ARG_OBJ, CallSiteDescriptor.ARG_OBJ, CallSiteDescriptor.ARG_OBJ), null)
    private val rvThrower = CallSiteDescriptor(
        byteArrayOf(CallSiteDescriptor.ARG_OBJ, CallSiteDescriptor.ARG_OBJ), null)
    private val targetTypeSite = CallSiteDescriptor(
        byteArrayOf(CallSiteDescriptor.ARG_OBJ, CallSiteDescriptor.ARG_OBJ), null)

    @JvmStatic
    fun p6typecheckrv(rv: SixModelObject?, routine: SixModelObject?, bypassType: SixModelObject?, tc: ThreadContext): SixModelObject? {
        val gcx = key.getGC(tc)
        val sig = routine!!.get_attribute_boxed(tc, gcx.Code, "$!signature", HINT_CODE_SIG)
        var rtype = sig!!.get_attribute_boxed(tc, gcx.Signature, "$!returns", HINT_SIG_RETURNS)
        if (rtype != null) {
            /* The return type could be generic. In that case we have
             * to call instantiate_generic before doing the type check. */
            val HOW = rtype.st.HOW
            val archetypesMeth = Ops.findmethod(HOW, "archetypes", tc)
            /* The type must ride along: DefiniteHOW's nullary archetypes()
             * answers its non-generic default, which under the dispatch
             * binder is exactly what a dropped extra argument produced. */
            Ops.invokeDirect(tc, archetypesMeth, targetTypeSite, arrayOf<Any?>(HOW, rtype))
            val Archetypes = Ops.result_o(tc.curFrame!!)
            val genericMeth = Ops.findmethodNonFatal(Archetypes, "generic", tc)
            if (genericMeth != null) {
                Ops.invokeDirect(tc, genericMeth, Ops.invocantCallSite, arrayOf<Any?>(Archetypes))
                if (Ops.istrue(Ops.result_o(tc.curFrame!!), tc) == 1L) {
                    val ig = Ops.findmethod(HOW, "instantiate_generic", tc)
                    val ContextRef = tc.gc.ContextRef!!
                    val cc = ContextRef.st.REPR.allocate(tc, ContextRef.st)
                    (cc as ContextRefInstance).context = tc.curFrame!!
                    Ops.invokeDirect(tc, ig, genIns, arrayOf<Any?>(HOW, rtype, cc))
                    rtype = Ops.result_o(tc.curFrame!!)
                    /* A generic that instantiated to a native type checks
                     * against its box: the routine body produces boxed
                     * values. Same mapping the raku-rv-typecheck-generic
                     * dispatcher applies on MoarVM. */
                    val ni = Ops.gethllsym("Raku", "NativeInstantiation", tc)
                    if (ni != null && Ops.isnull(ni) == 0L) {
                        val boxMeth = Ops.findmethodNonFatal(ni, "box", tc)
                        if (boxMeth != null) {
                            Ops.invokeDirect(tc, boxMeth, targetTypeSite,
                                arrayOf<Any?>(ni, rtype))
                            val boxed = Ops.result_o(tc.curFrame!!)
                            if (boxed != null && Ops.isnull(boxed) == 0L)
                                rtype = boxed
                        }
                    }
                }
            }

            val decontValue = Ops.decont(rv, tc)
            if (Ops.istype(decontValue, rtype, tc) == 0L) {
                /* Straight type check failed, but it's possible we're returning
                 * an Int that can unbox into an int or similar. */
                val spec = rtype!!.st.REPR.get_storage_spec(tc, rtype.st)
                if (spec.inlining == Inlining.REFERENCE || Ops.istype(rtype, decontValue!!.st.WHAT, tc) == 0L) {
                    if (Ops.istype(decontValue!!.st.WHAT, bypassType, tc) == 0L) {
                        val thrower = getThrower(tc, "X::TypeCheck::Return")
                        if (thrower == null)
                            throw ExceptionHandling.dieInternal(tc,
                                "Type check failed for return value")
                        else
                            Ops.invokeDirect(tc, thrower,
                                rvThrower, arrayOf<Any?>(decontValue, rtype))
                    }
                }
            }
        }
        return rv
    }

    private val baThrower = CallSiteDescriptor(
        byteArrayOf(CallSiteDescriptor.ARG_OBJ, CallSiteDescriptor.ARG_OBJ), null)

    @JvmStatic
    fun p6bindassert(value: SixModelObject?, type: SixModelObject?, tc: ThreadContext): SixModelObject? {
        val gcx = key.getGC(tc)
        if (type !== gcx.Mu) {
            val decont = Ops.decont(value, tc)
            if (Ops.istype(decont, type, tc) == 0L) {
                val thrower = getThrower(tc, "X::TypeCheck::Binding")
                if (thrower == null)
                    ExceptionHandling.dieInternal(tc,
                        "Type check failed in binding")
                else
                    Ops.invokeDirect(tc, thrower,
                        baThrower, arrayOf<Any?>(value, type))
            }
        }
        return value
    }

    @JvmStatic
    fun p6capturelex(codeObj: SixModelObject?, tc: ThreadContext): SixModelObject? {
        val gcx = key.getGC(tc)
        /* Only a Raku Code carries the handle to re-capture. Anything else
         * is handed straight back, as the raku-capture-lex-callers
         * dispatcher does on MoarVM -- an attribute's build closure, for
         * one, reaches here as a bare code ref. */
        if (codeObj == null || Ops.istype(codeObj, gcx.Code, tc) == 0L)
            return codeObj
        val closure = codeObj.get_attribute_boxed(tc,
                gcx.Code, "$!do", HINT_CODE_DO) as CodeRef
        val wantedStaticInfo = closure.staticInfo.outerStaticInfo
        if (tc.curFrame!!.codeRef.staticInfo === wantedStaticInfo)
            closure.outer = tc.curFrame
        else if (tc.curFrame!!.outer!!.codeRef.staticInfo === wantedStaticInfo)
            closure.outer = tc.curFrame!!.outer
        return codeObj
    }

    /** Captures the closure's outer from whichever calling frame runs the
     * static code its outer names, the way MoarVM's try-capture-lex-callers
     * syscall does. This is what lets a phaser cloned at frame exit close
     * over the live frames rather than whatever compile-time frames it was
     * created under. */
    @JvmStatic
    fun p6capturelexwhere(codeObj: SixModelObject?, tc: ThreadContext): SixModelObject? {
        val gcx = key.getGC(tc)
        /* Only a Raku Code carries the handle to re-capture. Anything else
         * is handed straight back, as the raku-capture-lex-callers
         * dispatcher does on MoarVM -- an attribute's build closure, for
         * one, arrives here as a bare code ref. */
        if (codeObj == null || Ops.istype(codeObj, gcx.Code, tc) == 0L)
            return codeObj
        val closure = codeObj.get_attribute_boxed(tc,
                gcx.Code, "$!do", HINT_CODE_DO) as CodeRef
        val wantedStaticInfo = closure.staticInfo.outerStaticInfo ?: return codeObj
        var frame = tc.curFrame
        while (frame != null) {
            if (frame.codeRef.staticInfo === wantedStaticInfo) {
                closure.outer = frame
                break
            }
            frame = frame.caller
        }
        return codeObj
    }

    @JvmStatic
    fun p6getouterctx(codeObj: SixModelObject?, tc: ThreadContext): SixModelObject {
        val gcx = key.getGC(tc)
        val theCodeObj = Ops.decont(codeObj, tc)
        val closure = theCodeObj!!.get_attribute_boxed(tc,
                gcx.Code, "$!do", HINT_CODE_DO) as CodeRef
        val ContextRef = tc.gc.ContextRef!!
        val wrap = ContextRef.st.REPR.allocate(tc, ContextRef.st)
        (wrap as ContextRefInstance).context = closure.outer!!
        return wrap
    }

    @JvmStatic
    fun p6captureouters2(capList: SixModelObject?, target: SixModelObject?, tc: ThreadContext): SixModelObject? {
        if (target !is CodeRef)
            ExceptionHandling.dieInternal(tc, "p6captureouters target must be a CodeRef")
        val cf = (target as CodeRef).outer
            ?: return capList
        val elems = capList!!.elems(tc)
        for (i in 0 until elems) {
            val closure = capList.at_pos_boxed(tc, i)
            val ctxToDiddle = (closure as CodeRef).outer
            ctxToDiddle!!.outer = cf
        }
        return capList
    }

    @JvmStatic
    fun p6bindattrinvres(obj: SixModelObject?, ch: SixModelObject?, name: String?, value: SixModelObject?, tc: ThreadContext): SixModelObject? {
        obj!!.bind_attribute_boxed(tc, Ops.decont(ch, tc),
            name, STable.NO_HINT, value)
        if (obj.sc != null)
            Ops.scwbObject(tc, obj)
        return obj
    }

    @JvmStatic
    fun getThrower(tc: ThreadContext, type: String?): SixModelObject? {
        val exHash = Ops.gethllsym("Raku", "P6EX", tc)
        return if (exHash == null) null else Ops.atkey(exHash, type, tc)
    }

    private fun find_common_ctx(ctx1: CallFrame?, ctx2: CallFrame?): CallFrame? {
        var c1 = ctx1
        var c2 = ctx2
        var depth1 = 0
        var depth2 = 0

        var ctx = c1
        while (ctx != null) {
            if (ctx === c2)
                return ctx
            ctx = ctx.caller
            depth1++
        }
        ctx = c2
        while (ctx != null) {
            if (ctx === c1)
                return ctx
            ctx = ctx.caller
            depth2++
        }
        while (depth1 > depth2) {
            c1 = c1!!.caller
            depth2++
        }
        while (depth2 > depth1) {
            c2 = c2!!.caller
            depth1++
        }
        while (c1 !== c2) {
            c1 = c1!!.caller
            c2 = c2!!.caller
        }
        return c1
    }

    private fun getremotelex(pad: CallFrame?, name: String): SixModelObject? { /* use for sub_find_pad */
        var curFrame = pad
        while (curFrame != null) {
            val found = curFrame.codeRef.staticInfo.oTryGetLexicalIdx(name)
            if (found != -1)
                return curFrame.oLexOrVivify(found)
            curFrame = curFrame.outer
        }
        return null
    }

    @JvmStatic
    fun tclc(`in`: String?, tc: ThreadContext): String {
        if (`in`!!.length == 0)
            return `in`
        val first = `in`.codePointAt(0)
        return String(Character.toChars(Character.toTitleCase(first))) +
            `in`.substring(Character.charCount(first)).lowercase()
    }

    @JvmStatic
    fun p6stateinit(tc: ThreadContext): Long {
        return if (tc.curFrame!!.stateInit) 1 else 0
    }

    @JvmStatic
    fun p6setfirstflag(codeObj: SixModelObject?, tc: ThreadContext): SixModelObject? {
        val tcx = key.getTC(tc)
        tcx.firstPhaserCodeBlock = codeObj
        return codeObj
    }

    @JvmStatic
    fun p6takefirstflag(tc: ThreadContext): Long {
        val tcx = key.getTC(tc)
        val matches = tcx.firstPhaserCodeBlock === tc.curFrame!!.codeRef
        tcx.firstPhaserCodeBlock = null
        return if (matches) 1 else 0
    }

    @JvmStatic
    fun p6setpre(tc: ThreadContext): SixModelObject? {
        val tcx = key.getTC(tc)
        tcx.prePhaserFrames.add(tc.curFrame!!)
        return null
    }

    @JvmStatic
    fun p6clearpre(tc: ThreadContext): SixModelObject? {
        val tcx = key.getTC(tc)
        tcx.prePhaserFrames.remove(tc.curFrame)
        return null
    }

    @JvmStatic
    fun p6inpre(tc: ThreadContext): Long {
        val tcx = key.getTC(tc)
        return if (tcx.prePhaserFrames.remove(tc.curFrame!!.caller)) 1 else 0
    }

    private val dispVivifier = CallSiteDescriptor(
        byteArrayOf(CallSiteDescriptor.ARG_OBJ, CallSiteDescriptor.ARG_OBJ,
                    CallSiteDescriptor.ARG_OBJ, CallSiteDescriptor.ARG_OBJ), null)
    private val dispThrower = CallSiteDescriptor(
        byteArrayOf(CallSiteDescriptor.ARG_STR), null)

    /* Sinking a statement used to compile to a `can`/`callmethod sink` pair
     * inline, which spends one invokedynamic call site per sunk statement.
     * The core setting has enough of them for that alone to push a class past
     * HotSpot's 65535-invokedynamic-per-class ceiling, so the whole thing
     * lives here instead. Returns the sinkee, as MoarVM's p6sink does. */
    @JvmStatic
    fun p6sink(obj: SixModelObject?, tc: ThreadContext): SixModelObject? {
        /* A value in a container is not sunk: the raku-sink dispatcher looks
         * at the sinkee without decontainerizing, so a Scalar an is-rw
         * routine returned keeps its contents unsunk. Scalar itself has no
         * sink method worth calling. */
        if (obj != null && obj.st.ContainerSpec == null && Ops.isconcrete(obj, tc) != 0L) {
            val meth = Ops.findmethodNonFatal(obj, "sink", tc)
            if (Ops.isnull(meth) == 0L)
                /* Through the dispatcher: sink resolves to a multi's proto. */
                Ops.invokeMethodViaDispatch(tc, meth, invocantCallSite, arrayOf<Any?>(obj))
        }
        return obj
    }

    private val invocantCallSite = CallSiteDescriptor(
        byteArrayOf(CallSiteDescriptor.ARG_OBJ), null)

    @JvmStatic
    fun p6finddispatcher(usage: String?, tc: ThreadContext): SixModelObject? {
        var dispatcher: SixModelObject? = null

        var ctx = tc.curFrame!!.caller
        while (ctx != null) {
            /* Do we have a dispatcher here? */
            val sci = ctx.codeRef.staticInfo
            val dispLexIdx = sci.oTryGetLexicalIdx("\$*DISPATCHER")
            if (dispLexIdx != -1) {
                val maybeDispatcher = ctx.oLexOrVivify(dispLexIdx)
                if (maybeDispatcher != null) {
                    dispatcher = maybeDispatcher
                    if (dispatcher is TypeObject) {
                        /* Need to vivify it. */
                        val meth = Ops.findmethod(dispatcher, "vivify_for", tc)
                        val p6sub = ctx.codeRef.codeObject

                        val ContextRef = tc.gc.ContextRef!!
                        val wrap = ContextRef.st.REPR.allocate(tc, ContextRef.st)
                        (wrap as ContextRefInstance).context = ctx

                        val CallCapture = tc.gc.CallCapture!!
                        val cc = CallCapture.st.REPR.allocate(tc, CallCapture.st) as CallCaptureInstance
                        cc.descriptor = ctx.csd
                        cc.args = ctx.args

                        Ops.invokeDirect(tc, meth,
                            dispVivifier, arrayOf<Any?>(dispatcher, p6sub, wrap, cc))
                        dispatcher = Ops.result_o(tc.curFrame!!)
                        ctx.oLex!![dispLexIdx] = dispatcher
                    }
                    break
                }
            }

            /* Follow dynamic chain. */
            ctx = ctx.caller
        }

        if (dispatcher == null) {
            val thrower = getThrower(tc, "X::NoDispatcher")
            if (thrower == null) {
                ExceptionHandling.dieInternal(tc,
                    usage + " is not in the dynamic scope of a dispatcher")
            } else {
                Ops.invokeDirect(tc, thrower,
                    dispThrower, arrayOf<Any?>(usage))
            }
        }

        return dispatcher
    }

    @JvmStatic
    fun p6argsfordispatcher(disp: SixModelObject?, tc: ThreadContext): SixModelObject {
        var result: SixModelObject? = null

        var ctx = tc.curFrame
        while (ctx != null) {
            /* Do we have the dispatcher we're looking for? */
            val sci = ctx.codeRef.staticInfo
            val dispLexIdx = sci.oTryGetLexicalIdx("\$*DISPATCHER")
            if (dispLexIdx != -1) {
                val maybeDispatcher = ctx.oLexOrVivify(dispLexIdx)
                if (maybeDispatcher === disp) {
                    /* Found; grab args. */
                    val CallCapture = tc.gc.CallCapture!!
                    val cc = CallCapture.st.REPR.allocate(tc, CallCapture.st) as CallCaptureInstance
                    cc.descriptor = ctx.csd
                    cc.args = ctx.args
                    result = cc
                    break
                }
            }

            /* Follow dynamic chain. */
            ctx = ctx.caller
        }

        if (result == null)
            throw ExceptionHandling.dieInternal(tc,
                "Could not find arguments for dispatcher")
        return result
    }

    @JvmStatic
    fun p6staticouter(code: SixModelObject?, tc: ThreadContext): SixModelObject? {
        if (code is CodeRef) {
            /* An outermost frame (a comp unit's mainline) has no static
             * outer; answer null rather than dying, the way MoarVM does.
             * Backtrace.nice walks outers with exactly this. */
            val outer = code.staticInfo.outerStaticInfo
                ?: return Ops.createNull(tc)
            return outer.staticCode ?: Ops.createNull(tc)
        }
        else
            throw ExceptionHandling.dieInternal(tc, "p6staticouter must be used on a CodeRef")
    }

    @JvmStatic
    fun jvmrakudointerop(tc: ThreadContext): SixModelObject {
        val gcx = key.getGC(tc)
        return BootJavaInterop.RuntimeSupport.boxJava(gcx.rakudoInterop,
            gcx.rakudoInterop!!.getSTableForClass(RakudoJavaInterop::class.java))
    }
}
