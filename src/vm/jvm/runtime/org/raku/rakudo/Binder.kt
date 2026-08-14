package org.raku.rakudo

import it.unimi.dsi.fastutil.objects.Object2IntOpenHashMap

import org.raku.nqp.runtime.CallFrame
import org.raku.nqp.runtime.CallSiteDescriptor
import org.raku.nqp.runtime.Ops
import org.raku.nqp.runtime.ThreadContext
import org.raku.nqp.sixmodel.REPR
import org.raku.nqp.sixmodel.STable
import org.raku.nqp.sixmodel.SixModelObject
import org.raku.nqp.sixmodel.StorageSpec
import org.raku.nqp.sixmodel.reprs.ContextRefInstance
import org.raku.nqp.sixmodel.reprs.P6int
import org.raku.nqp.sixmodel.reprs.P6str
import org.raku.nqp.sixmodel.reprs.P6num
import org.raku.nqp.sixmodel.reprs.P6OpaqueREPRData

object Binder {
    /* Possible results of binding. */
    const val BIND_RESULT_OK       = 0
    const val BIND_RESULT_FAIL     = 1
    const val BIND_RESULT_JUNCTION = 2

    /* Compile time trial binding result indicators. */
    const val TRIAL_BIND_NOT_SURE =  0  /* Plausible, but need to check at runtime. */
    const val TRIAL_BIND_OK       =  1  /* Bind will always work out. */
    const val TRIAL_BIND_NO_WAY   = -1  /* Bind could never work out. */

    /* Flags. */
    private const val SIG_ELEM_BIND_CAPTURE        = 1
    private const val SIG_ELEM_BIND_PRIVATE_ATTR   = 2
    private const val SIG_ELEM_BIND_PUBLIC_ATTR    = 4
    private const val SIG_ELEM_BIND_ATTRIBUTIVE    = (SIG_ELEM_BIND_PRIVATE_ATTR or SIG_ELEM_BIND_PUBLIC_ATTR)
    private const val SIG_ELEM_SLURPY_POS          = 8
    private const val SIG_ELEM_SLURPY_NAMED        = 16
    private const val SIG_ELEM_SLURPY_LOL          = 32
    private const val SIG_ELEM_INVOCANT            = 64
    private const val SIG_ELEM_MULTI_INVOCANT      = 128
    private const val SIG_ELEM_IS_RW               = 256
    private const val SIG_ELEM_IS_COPY             = 512
    private const val SIG_ELEM_IS_RAW              = 1024
    private const val SIG_ELEM_IS_OPTIONAL         = 2048
    private const val SIG_ELEM_ARRAY_SIGIL         = 4096
    private const val SIG_ELEM_HASH_SIGIL          = 8192
    private const val SIG_ELEM_DEFAULT_FROM_OUTER  = 16384
    private const val SIG_ELEM_IS_CAPTURE          = 32768
    private const val SIG_ELEM_UNDEFINED_ONLY      = 65536
    private const val SIG_ELEM_DEFINED_ONLY        = 131072
    private const val SIG_ELEM_DEFINEDNES_CHECK    = (SIG_ELEM_UNDEFINED_ONLY or SIG_ELEM_DEFINED_ONLY)
    private const val SIG_ELEM_TYPE_GENERIC        = 524288
    private const val SIG_ELEM_DEFAULT_IS_LITERAL  = 1048576
    private const val SIG_ELEM_NATIVE_INT_VALUE    = 2097152
    private const val SIG_ELEM_NATIVE_UINT_VALUE   = 134217728
    private const val SIG_ELEM_NATIVE_NUM_VALUE    = 4194304
    private const val SIG_ELEM_NATIVE_STR_VALUE    = 8388608
    private const val SIG_ELEM_NATIVE_VALUE        = (SIG_ELEM_NATIVE_INT_VALUE or SIG_ELEM_NATIVE_UINT_VALUE or SIG_ELEM_NATIVE_NUM_VALUE or SIG_ELEM_NATIVE_STR_VALUE)
    private const val SIG_ELEM_SLURPY_ONEARG       = 16777216
    private const val SIG_ELEM_SLURPY              = (SIG_ELEM_SLURPY_POS or SIG_ELEM_SLURPY_NAMED or SIG_ELEM_SLURPY_LOL or SIG_ELEM_SLURPY_ONEARG)
    private const val SIG_ELEM_CODE_SIGIL          = 33554432
    private const val SIG_ELEM_IS_COERCIVE         = 67108864

    /* Hints for Parameter attributes. */
    private const val HINT_variable_name = 0L
    private const val HINT_named_names = 1L
    private const val HINT_type_captures = 2L
    private const val HINT_flags = 3L
    private const val HINT_type = 4L
    private const val HINT_post_constraints = 5L
    private const val HINT_sub_signature = 6L
    private const val HINT_default_value = 7L
    private const val HINT_container_descriptor = 8L
    private const val HINT_attr_package = 9L

    /* Other hints. */
    private const val HINT_ENUMMAP_storage = 0L
    private const val HINT_CAPTURE_list = 0L
    private const val HINT_CAPTURE_hash = 1L
    private const val HINT_LIST_reified = 0L
    private const val HINT_SIG_params = 0L

    private fun createBox(tc: ThreadContext, gcx: RakOps.GlobalExt, arg: Any?, flag: Int): SixModelObject {
        return when (flag) {
            CallSiteDescriptor.ARG_INT.toInt() ->
                Ops.box_i(arg as Long, gcx.Int, tc)
            CallSiteDescriptor.ARG_UINT.toInt() ->
                Ops.box_u(arg as Long, gcx.Int, tc)
            CallSiteDescriptor.ARG_NUM.toInt() ->
                Ops.box_n(arg as Double, gcx.Num, tc)
            CallSiteDescriptor.ARG_STR.toInt() ->
                Ops.box_s(arg as String?, gcx.Str, tc)
            else ->
                throw RuntimeException("Impossible case reached in createBox")
        }
    }

    private fun arityFail(tc: ThreadContext, gcx: RakOps.GlobalExt, cf: CallFrame,
            params: SixModelObject, numParams: Int, numPosArgs: Int, tooMany: Boolean): String {
        var arity = 0
        var count = 0
        val fail = if (tooMany) "Too many" else "Too few"

        /* Work out how many we could have been passed. */
        for (i in 0 until numParams) {
            val param = params.at_pos_boxed(tc, i.toLong())!!
            param.get_attribute_native(tc, gcx.Parameter, "$!flags", HINT_flags)
            val flags = tc.native_i.toInt()
            val namedNames = param.get_attribute_boxed(tc,
                gcx.Parameter, "@!named_names", HINT_named_names)

            if (namedNames != null)
                continue
            if ((flags and SIG_ELEM_SLURPY_NAMED) != 0)
                continue
            if ((flags and SIG_ELEM_SLURPY) != 0) {
                count = -1000 // cargo-culted from BOOTSTRAP.nqp: "in case a pos can sneak past a slurpy somehow"
            }
            else if ((flags and SIG_ELEM_IS_OPTIONAL) != 0) {
                count++
            }
            else {
                count++
                arity++
            }
        }

        var routineName = cf.codeRef.name
        if (routineName == null || routineName.isEmpty())
            routineName = "<anon>"

        /* Now generate decent error. */
        if (arity == count)
            return String.format(
                "%s positionals passed to '%s'; expected %d arguments but got %d",
                fail, routineName, arity, numPosArgs)
        else if (count <= -1)
            return String.format(
                "%s positionals passed to '%s'; expected at least %d arguments but got only %d",
                fail, routineName, arity, numPosArgs)
        else
            return String.format(
                "%s positionals passed to '%s'; expected %d %s %d arguments but got %d",
                fail, routineName, arity, if (arity + 1 == count) "or" else "to", count, numPosArgs)
    }

    /* Binds any type captures. */
    @JvmStatic
    fun bindTypeCaptures(tc: ThreadContext, typeCaps: SixModelObject, cf: CallFrame, type: SixModelObject?) {
        val elems = typeCaps.elems(tc)
        val sci = cf.codeRef.staticInfo
        for (i in 0 until elems) {
            typeCaps.at_pos_native(tc, i)
            val name = tc.native_s
            cf.oLex!![sci.oTryGetLexicalIdx(name!!)] = type
        }
    }

    /* Assigns an attributive parameter to the desired attribute. */
    private fun assignAttributive(tc: ThreadContext, cf: CallFrame, varName: String,
            paramFlags: Int, attrPackage: SixModelObject, value: SixModelObject?, error: Array<Any?>?): Int {
        /* Find self. */
        val sci = cf.codeRef.staticInfo
        val selfIdx = sci.oTryGetLexicalIdx("self")
        val self: SixModelObject?
        if (selfIdx == -1) {
            self = Ops.getlexouter("self", tc)
            if (self == null) {
                if (error != null)
                    error[0] = String.format(
                        "Unable to bind attributive parameter '%s' - could not find self",
                        varName)
                return BIND_RESULT_FAIL
            }
        }
        else {
            self = cf.oLex!![selfIdx]
        }

        /* If it's private, just need to fetch the attribute. */
        val assignee: SixModelObject?
        if ((paramFlags and SIG_ELEM_BIND_PRIVATE_ATTR) != 0) {
            /* If we have a native Attribute we can't get a container for it, and
               since *trying* to get a container would throw already, we first check
               if the target Attribute is native. */
            var hint = -1
            for (map in (attrPackage.st.REPRData as P6OpaqueREPRData).nameToHintMap!!) {
                hint = map!!.getOrDefault(varName, -1)
            }
            var attrREPR: REPR? = null
            if ((attrPackage.st.REPRData as P6OpaqueREPRData).flattenedSTables!![hint] != null) {
                /* We sometimes don't have flattenedSTables. I'm not sure that's okay, honestly... */
                attrREPR = (attrPackage.st.REPRData as P6OpaqueREPRData).flattenedSTables!![hint]!!.REPR
            }
            when (attrREPR) {
                is P6int ->
                    Ops.bindattr_i(self, attrPackage, varName, Ops.unbox_i(value, tc), tc)
                is P6num ->
                    Ops.bindattr_n(self, attrPackage, varName, Ops.unbox_n(value, tc), tc)
                is P6str ->
                    Ops.bindattr_s(self, attrPackage, varName, Ops.unbox_s(value, tc), tc)
                else -> {
                    /* ...but we'll just assume it's probably some boxed Attribute. */
                    assignee = self!!.get_attribute_boxed(tc, attrPackage, varName, STable.NO_HINT)
                    RakOps.p6store(assignee, value, tc)
                }
            }
        }
        /* Otherwise if it's public, do a method call to get the assignee. */
        else {
            throw RuntimeException("$.x parameters NYI")
        }
        return BIND_RESULT_OK
    }

    /* Returns an appropriate failure mode (junction fail or normal fail). */
    private fun juncOrFail(tc: ThreadContext, gcx: RakOps.GlobalExt, value: SixModelObject?): Int {
        return if (value!!.st.WHAT === gcx.Junction && Ops.isconcrete(value, tc) != 0L)
            BIND_RESULT_JUNCTION
        else
            BIND_RESULT_FAIL
    }

    /* Binds a single argument into the lexpad, after doing any checks that are
     * needed. Also handles any type captures. If there is a sub signature, then
     * re-enters the binder. Returns one of the BIND_RESULT_* codes. */
    private val genIns = CallSiteDescriptor(
        byteArrayOf(CallSiteDescriptor.ARG_OBJ, CallSiteDescriptor.ARG_OBJ, CallSiteDescriptor.ARG_OBJ), null)
    private val targetType = CallSiteDescriptor(
        byteArrayOf(CallSiteDescriptor.ARG_OBJ, CallSiteDescriptor.ARG_OBJ), null)
    private val ACCEPTS_o = CallSiteDescriptor(
        byteArrayOf(CallSiteDescriptor.ARG_OBJ, CallSiteDescriptor.ARG_OBJ), null)
    private val ACCEPTS_i = CallSiteDescriptor(
        byteArrayOf(CallSiteDescriptor.ARG_OBJ, CallSiteDescriptor.ARG_INT), null)
    private val ACCEPTS_u = CallSiteDescriptor(
        byteArrayOf(CallSiteDescriptor.ARG_OBJ, CallSiteDescriptor.ARG_UINT), null)
    private val ACCEPTS_n = CallSiteDescriptor(
        byteArrayOf(CallSiteDescriptor.ARG_OBJ, CallSiteDescriptor.ARG_NUM), null)
    private val ACCEPTS_s = CallSiteDescriptor(
        byteArrayOf(CallSiteDescriptor.ARG_OBJ, CallSiteDescriptor.ARG_STR), null)
    private val bindParamThrower = CallSiteDescriptor(
        byteArrayOf(CallSiteDescriptor.ARG_OBJ, CallSiteDescriptor.ARG_OBJ,
            CallSiteDescriptor.ARG_STR, CallSiteDescriptor.ARG_OBJ,
            CallSiteDescriptor.ARG_INT
        ), null)
    private val bindConcreteThrower = CallSiteDescriptor(
        byteArrayOf(CallSiteDescriptor.ARG_STR, CallSiteDescriptor.ARG_STR,
            CallSiteDescriptor.ARG_STR, CallSiteDescriptor.ARG_STR,
            CallSiteDescriptor.ARG_INT, CallSiteDescriptor.ARG_INT
        ), null)
    private val paramReadWriteThrower = CallSiteDescriptor(
        byteArrayOf(CallSiteDescriptor.ARG_OBJ, CallSiteDescriptor.ARG_STR), null)

    private fun bindOneParam(tc: ThreadContext, gcx: RakOps.GlobalExt, cf: CallFrame, param: SixModelObject,
            origArg: Any?, origFlag: Byte, noNomTypeCheck: Boolean, isSlurpyNamed: Boolean, error: Array<Any?>?): Int {
        /* Get parameter flags and variable name. */
        param.get_attribute_native(tc, gcx.Parameter, "$!flags", HINT_flags)
        val paramFlags = tc.native_i.toInt()
        param.get_attribute_native(tc, gcx.Parameter, "$!variable_name", HINT_variable_name)
        var varName = tc.native_s
        var hasVarName = true
        if (varName == null || varName.isEmpty()) {
            varName = "<anon>"
            hasVarName = false
        }
        if (RakOps.DEBUG_MODE)
            System.err.println(varName)

        /* We'll put the value to bind into one of the following locals, and
         * flag will indicate what type of thing it is. */
        val flag: Int
        var arg_i: Long = 0
        var arg_n: Double = 0.0
        var arg_s: String? = null
        var arg_o: SixModelObject? = null

        /* Check if boxed/unboxed expectations are met. */
        val desiredNative = paramFlags and SIG_ELEM_NATIVE_VALUE
        val is_rw = (paramFlags and SIG_ELEM_IS_RW) != 0
        val gotNative = origFlag.toInt() and (CallSiteDescriptor.ARG_INT.toInt() or CallSiteDescriptor.ARG_UINT.toInt() or CallSiteDescriptor.ARG_NUM.toInt() or CallSiteDescriptor.ARG_STR.toInt())
        if (is_rw && desiredNative != 0) {
            when (desiredNative) {
            SIG_ELEM_NATIVE_INT_VALUE ->
                if (gotNative != 0 || Ops.iscont_i(origArg as SixModelObject?) == 0L) {
                    if (error != null)
                        error[0] = String.format(
                            "Expected a modifiable native int argument for '%s'",
                            varName)
                    return BIND_RESULT_FAIL
                }
            SIG_ELEM_NATIVE_UINT_VALUE ->
                if (gotNative != 0 || Ops.iscont_u(origArg as SixModelObject?) == 0L) {
                    if (error != null)
                        error[0] = String.format(
                            "Expected a modifiable native unsigned int argument for '%s'",
                            varName)
                    return BIND_RESULT_FAIL
                }
            SIG_ELEM_NATIVE_NUM_VALUE ->
                if (gotNative != 0 || Ops.iscont_n(origArg as SixModelObject?) == 0L) {
                    if (error != null)
                        error[0] = String.format(
                            "Expected a modifiable native num argument for '%s'",
                            varName)
                    return BIND_RESULT_FAIL
                }
            SIG_ELEM_NATIVE_STR_VALUE ->
                if (gotNative != 0 || Ops.iscont_s(origArg as SixModelObject?) == 0L) {
                    if (error != null)
                        error[0] = String.format(
                            "Expected a modifiable native str argument for '%s'",
                            varName)
                    return BIND_RESULT_FAIL
                }
            }
            flag = CallSiteDescriptor.ARG_OBJ.toInt()
            arg_o = origArg as SixModelObject?
        }
        else if (desiredNative == 0 && gotNative == CallSiteDescriptor.ARG_OBJ.toInt()) {
            flag = gotNative
            arg_o = origArg as SixModelObject?
        }
        else if (desiredNative == SIG_ELEM_NATIVE_INT_VALUE && gotNative == CallSiteDescriptor.ARG_INT.toInt()) {
            flag = gotNative
            arg_i = origArg as Long
        }
        else if (desiredNative == SIG_ELEM_NATIVE_UINT_VALUE && gotNative == CallSiteDescriptor.ARG_UINT.toInt()) {
            flag = gotNative
            arg_i = origArg as Long
        }
        else if (desiredNative == SIG_ELEM_NATIVE_NUM_VALUE && gotNative == CallSiteDescriptor.ARG_NUM.toInt()) {
            flag = gotNative
            arg_n = origArg as Double
        }
        else if (desiredNative == SIG_ELEM_NATIVE_STR_VALUE && gotNative == CallSiteDescriptor.ARG_STR.toInt()) {
            flag = gotNative
            arg_s = origArg as String?
        }
        else if (desiredNative == 0) {
            /* We need to do a boxing operation. */
            flag = CallSiteDescriptor.ARG_OBJ.toInt()
            arg_o = createBox(tc, gcx, origArg, gotNative)
        }
        else {
            /* We need to do an unboxing operation. */
            val unboxVal = Ops.decont(origArg as SixModelObject?, tc)!!
            val spec = unboxVal.st.REPR.get_storage_spec(tc, unboxVal.st)
            when (desiredNative) {
                SIG_ELEM_NATIVE_INT_VALUE ->
                    if ((spec.can_box.toInt() and StorageSpec.CAN_BOX_INT.toInt()) != 0) {
                        flag = CallSiteDescriptor.ARG_INT.toInt()
                        arg_i = unboxVal.get_int(tc)
                    }
                    else {
                        if (error != null)
                            error[0] = String.format(
                                "Cannot unbox argument to '%s' as a native int",
                                varName)
                        return BIND_RESULT_FAIL
                    }
                SIG_ELEM_NATIVE_UINT_VALUE ->
                    if ((spec.can_box.toInt() and StorageSpec.CAN_BOX_INT.toInt()) != 0) {
                        flag = CallSiteDescriptor.ARG_UINT.toInt()
                        arg_i = unboxVal.get_int(tc)
                    }
                    else {
                        if (error != null)
                            error[0] = String.format(
                                "Cannot unbox argument to '%s' as a native int",
                                varName)
                        return BIND_RESULT_FAIL
                    }
                SIG_ELEM_NATIVE_NUM_VALUE ->
                    if ((spec.can_box.toInt() and StorageSpec.CAN_BOX_NUM.toInt()) != 0) {
                        flag = CallSiteDescriptor.ARG_NUM.toInt()
                        arg_n = unboxVal.get_num(tc)
                    }
                    else {
                        if (error != null)
                            error[0] = String.format(
                                "Cannot unbox argument to '%s' as a native num",
                                varName)
                        return BIND_RESULT_FAIL
                    }
                SIG_ELEM_NATIVE_STR_VALUE ->
                    if ((spec.can_box.toInt() and StorageSpec.CAN_BOX_STR.toInt()) != 0) {
                        flag = CallSiteDescriptor.ARG_STR.toInt()
                        arg_s = unboxVal.get_str(tc)
                    }
                    else {
                        if (error != null)
                            error[0] = String.format(
                                "Cannot unbox argument to '%s' as a native str",
                                varName)
                        return BIND_RESULT_FAIL
                    }
                else -> {
                    if (error != null)
                        error[0] = String.format(
                            "Cannot unbox argument to '%s' as a native type",
                            varName)
                    return BIND_RESULT_FAIL
                }
            }
        }

        /* By this point, we'll either have an object that we might be able to
         * bind if it passes the type check, or a native value that needs no
         * further checking. */
        var decontValue: SixModelObject? = null
        var didHLLTransform = false
        var paramType = param.get_attribute_boxed(tc, gcx.Parameter, "$!type", HINT_type)
        val ContextRef: SixModelObject?
        var HOW: SixModelObject?
        if (flag == CallSiteDescriptor.ARG_OBJ.toInt() && !(is_rw && desiredNative != 0)) {
            /* We need to work on the decontainerized value. */
            decontValue = Ops.decont(arg_o, tc)

            /* HLL map it as needed. */
            val beforeHLLize = decontValue
            decontValue = Ops.hllize(decontValue, tc)
            if (decontValue !== beforeHLLize)
                didHLLTransform = true

            /* Skip nominal type check if not needed. */
            if (!noNomTypeCheck) {
                /* Is the nominal type generic and in need of instantiation? (This
                 * can happen in (::T, T) where we didn't learn about the type until
                 * during the signature bind.) */
                if ((paramFlags and SIG_ELEM_TYPE_GENERIC) != 0) {
                    HOW = paramType!!.st.HOW
                    val ig = Ops.findmethod(HOW,
                        "instantiate_generic", tc)
                    ContextRef = tc.gc.ContextRef
                    val cc = ContextRef!!.st.REPR.allocate(tc, ContextRef.st)
                    (cc as ContextRefInstance).context = cf
                    Ops.invokeDirect(tc, ig, genIns,
                        arrayOf<Any?>(HOW, paramType, cc))
                    paramType = Ops.result_o(tc.curFrame!!)
                }

                /* If the expected type is Positional, see if we need to do the
                 * positional bind failover. */
                if (paramType === gcx.Positional) {
                    if (Ops.istype_nd(arg_o, gcx.PositionalBindFailover, tc) != 0L) {
                        val ig = Ops.findmethod(arg_o, "cache", tc)
                        Ops.invokeDirect(tc, ig, Ops.invocantCallSite, arrayOf<Any?>(arg_o))
                        arg_o = Ops.result_o(tc.curFrame!!)
                        decontValue = Ops.decont(arg_o, tc)
                    }
                    else if (Ops.istype_nd(decontValue, gcx.PositionalBindFailover, tc) != 0L) {
                        val ig = Ops.findmethod(decontValue, "cache", tc)
                        Ops.invokeDirect(tc, ig, Ops.invocantCallSite, arrayOf<Any?>(decontValue))
                        decontValue = Ops.result_o(tc.curFrame!!)
                    }
                }

                /* If not, do the check. If the wanted nominal type is Mu, then
                 * anything goes.
                 * When binding a slurpy named hash while compiling the setting don't check for Associative.
                 */
                if (paramType !== gcx.Mu && !(isSlurpyNamed && paramType === gcx.Associative) && Ops.istype_nd(decontValue, paramType, tc) == 0L) {
                    /* Type check failed; produce error if needed. */

                    /* Try to figure out the most helpful name for the expected. */
                    val expectedType: SixModelObject?
                    val postConstraints = param.get_attribute_boxed(tc, gcx.Parameter,
                            "$!post_constraints", HINT_post_constraints)
                    if (postConstraints != null) {
                        val consType = postConstraints.at_pos_boxed(tc, 0)
                        expectedType = if (Ops.istype(consType, gcx.Code, tc) != 0L)
                            paramType!!.st.WHAT
                        else
                            consType!!.st.WHAT
                    }
                    else {
                        expectedType = paramType!!.st.WHAT
                    }

                    if (error != null) {
                        val thrower = RakOps.getThrower(tc, "X::TypeCheck::Binding::Parameter")
                        if (thrower != null) {
                            error[0] = thrower
                            error[1] = bindParamThrower
                            error[2] = arrayOf<Any?>(decontValue, expectedType!!.st.WHAT,
                                varName, param, 0L)
                        }
                        else {
                            error[0] = String.format(
                                "Nominal type check failed for parameter '%s'",
                                varName)
                        }
                    }

                    /* Report junction failure mode if it's a junction. */
                    return juncOrFail(tc, gcx, decontValue)
                }

                /* Also enforce definedness check */
                if ((paramFlags and SIG_ELEM_DEFINEDNES_CHECK) != 0) {

                    /* Don't check decontValue for concreteness though, but arg_o,
                       seeing as we don't have a isconcrete_nodecont */
                    val shouldBeConcrete = (paramFlags and SIG_ELEM_DEFINED_ONLY) != 0 && Ops.isconcrete(arg_o, tc) != 1L
                    if (shouldBeConcrete || ((paramFlags and SIG_ELEM_UNDEFINED_ONLY) != 0 && Ops.isconcrete(arg_o, tc) == 1L)) {
                        if (error != null) {
                            val typeName = Ops.typeName(param.get_attribute_boxed(tc,
                                gcx.Parameter, "$!type", HINT_type), tc)
                            val argName = Ops.typeName(arg_o, tc)
                            var methodName = cf.codeRef.name
                            val thrower = RakOps.getThrower(tc, "X::Parameter::InvalidConcreteness")
                            if (thrower != null) {
                                error[0] = thrower
                                error[1] = bindConcreteThrower
                                error[2] = arrayOf<Any?>(typeName, argName, methodName,
                                    varName, if (shouldBeConcrete) 1L else 0L,
                                    (paramFlags and SIG_ELEM_INVOCANT).toLong())
                            }
                            else {
                                if (methodName == null || methodName.isEmpty())
                                    methodName = "<anon>"
                                error[0] = if ((paramFlags and SIG_ELEM_INVOCANT) != 0)
                                    if (shouldBeConcrete)
                                        String.format(
                                            "Invocant of method '%s' must be an object instance of type '%s', not a type object of type '%s'.  Did you forget a '.new'?",
                                            methodName, typeName, argName)
                                    else
                                        String.format(
                                            "Invocant of method '%s' must be a type object of type '%s', not an object instance of type '%s'.  Did you forget a 'multi'?",
                                            methodName, typeName, argName)
                                else
                                    if (shouldBeConcrete)
                                        String.format(
                                            "Parameter '%s' of routine '%s' must be an object instance of type '%s', not a type object of type '%s'.  Did you forget a '.new'?",
                                            varName, methodName, typeName, argName)
                                    else
                                        String.format(
                                            "Parameter '%s' of routine '%s' must be a type object of type '%s', not an object instance of type '%s'.  Did you forget a 'multi'?",
                                            varName, methodName, typeName, argName)
                            }
                        }
                        return juncOrFail(tc, gcx, decontValue)
                    }
                }
            }
        }

        /* Type captures. */
        val typeCaps = param.get_attribute_boxed(tc, gcx.Parameter,
            "@!type_captures", HINT_type_captures)
        if (typeCaps != null)
            bindTypeCaptures(tc, typeCaps, cf, decontValue!!.st.WHAT)

        /* Do a coercion, if one is needed. */
        HOW = paramType!!.st.HOW
        val archetypesMeth = Ops.findmethod(HOW, "archetypes", tc)
        Ops.invokeDirect(tc, archetypesMeth, Ops.invocantCallSite, arrayOf<Any?>(HOW))
        val Archetypes = Ops.result_o(tc.curFrame!!)
        val coerciveMeth = Ops.findmethodNonFatal(Archetypes, "coercive", tc)
        if (coerciveMeth != null) {
            Ops.invokeDirect(tc, coerciveMeth, Ops.invocantCallSite, arrayOf<Any?>(Archetypes))
            if (Ops.istrue(Ops.result_o(tc.curFrame!!), tc) == 1L) {
                /* Coercing natives not possible - nothing to call a method on. */
                if (flag != CallSiteDescriptor.ARG_OBJ.toInt()) {
                    if (error != null)
                        error[0] = String.format(
                            "Unable to coerce natively typed parameter '%s'",
                            varName)
                    return BIND_RESULT_FAIL
                }

                val coerceMeth = Ops.findmethod(HOW, "coerce", tc)
                Ops.invokeDirect(tc, coerceMeth, genIns, arrayOf<Any?>(HOW, paramType, arg_o))
                arg_o = Ops.result_o(tc.curFrame!!)
                decontValue = Ops.decont(arg_o, tc)
            }
        }

        /* If it's not got attributive binding, we'll go about binding it into the
         * lex pad. */
        val sci = cf.codeRef.staticInfo
        if ((paramFlags and SIG_ELEM_BIND_ATTRIBUTIVE) == 0) {
            /* Is it native? If so, just go ahead and bind it. */
            if (flag != CallSiteDescriptor.ARG_OBJ.toInt()) {
                if (hasVarName) {
                    when (flag) {
                        CallSiteDescriptor.ARG_INT.toInt() ->
                            cf.iLex!![sci.iTryGetLexicalIdx(varName)] = arg_i
                        CallSiteDescriptor.ARG_UINT.toInt() ->
                            cf.iLex!![sci.uTryGetLexicalIdx(varName)] = arg_i
                        CallSiteDescriptor.ARG_NUM.toInt() ->
                            cf.nLex!![sci.nTryGetLexicalIdx(varName)] = arg_n
                        CallSiteDescriptor.ARG_STR.toInt() ->
                            cf.sLex!![sci.sTryGetLexicalIdx(varName)] = arg_s
                    }
                }
            }

            /* Otherwise it's some objecty case. */
            else if (is_rw) {
                if (Ops.isrwcont(arg_o, tc) == 1L) {
                    if (hasVarName)
                        cf.oLex!![sci.oTryGetLexicalIdx(varName)] = arg_o
                } else {
                    val thrower = RakOps.getThrower(tc, "X::Parameter::RW")
                    if (thrower == null) {
                        error!![0] = "Parameter expected a writable container"
                    } else {
                        error!![0] = thrower
                        error[1] = paramReadWriteThrower
                        error[2] = arrayOf<Any?>(decontValue, varName)
                    }
                    return BIND_RESULT_FAIL
                }

            }
            else if (hasVarName) {
                if ((paramFlags and SIG_ELEM_IS_RAW) != 0) {
                    /* Just bind the thing as is into the lexpad. */
                    cf.oLex!![sci.oTryGetLexicalIdx(varName)] = if (didHLLTransform) decontValue else arg_o
                }
                else {
                    /* If it's an array, copy means make a new one and store,
                     * and a normal bind is a straightforward binding plus
                     * adding a constraint. */
                    if ((paramFlags and SIG_ELEM_ARRAY_SIGIL) != 0) {
                        var bindee = decontValue
                        if ((paramFlags and SIG_ELEM_IS_COPY) != 0) {
                            val BOOTArray = tc.gc.BOOTArray!!
                            bindee = gcx.Array.st.REPR.allocate(tc, gcx.Array.st)
                            bindee.bind_attribute_boxed(tc, gcx.List, "$!reified",
                                HINT_LIST_reified, BOOTArray.st.REPR.allocate(tc, BOOTArray.st))
                            RakOps.p6store(bindee, decontValue, tc)
                        }
                        cf.oLex!![sci.oTryGetLexicalIdx(varName)] = bindee
                    }

                    /* If it's a hash, similar approach to array. */
                    else if ((paramFlags and SIG_ELEM_HASH_SIGIL) != 0) {
                        var bindee = decontValue
                        if ((paramFlags and SIG_ELEM_IS_COPY) != 0) {
                            val BOOTHash = tc.gc.BOOTHash!!
                            bindee = gcx.Hash.st.REPR.allocate(tc, gcx.Hash.st)
                            bindee.bind_attribute_boxed(tc, gcx.Map, "$!storage",
                                HINT_ENUMMAP_storage, BOOTHash.st.REPR.allocate(tc, BOOTHash.st))
                            RakOps.p6store(bindee, decontValue, tc)
                        }
                        cf.oLex!![sci.oTryGetLexicalIdx(varName)] = bindee
                    }

                    /* If it's a scalar, we always need to wrap it into a new
                     * container and store it, for copy or ro case (the rw bit
                     * in the container descriptor takes care of the rest). */
                    else {
                        var wrap = (paramFlags and SIG_ELEM_IS_COPY) != 0
                        if (!wrap && paramType != null && gcx.Iterable != null) {
                            wrap = Ops.istype(gcx.Iterable, paramType, tc) != 0L ||
                                Ops.istype(paramType, gcx.Iterable, tc) != 0L
                        }
                        if (wrap || varName == "\$_") {
                            val stScalar = gcx.Scalar.st
                            val new_cont = stScalar.REPR.allocate(tc, stScalar)
                            val desc = param.get_attribute_boxed(tc, gcx.Parameter,
                                "$!container_descriptor", HINT_container_descriptor)
                            new_cont.bind_attribute_boxed(tc, gcx.Scalar, "$!descriptor",
                                RakudoContainerSpec.HINT_descriptor.toLong(), desc)
                            new_cont.bind_attribute_boxed(tc, gcx.Scalar, "$!value",
                                RakudoContainerSpec.HINT_value.toLong(), decontValue)
                            cf.oLex!![sci.oTryGetLexicalIdx(varName)] = new_cont
                        }
                        else {
                            cf.oLex!![sci.oTryGetLexicalIdx(varName)] = decontValue
                        }
                    }
                }
            }
        }

        /* Is it the invocant? If so, also have to bind to self lexical. */
        if ((paramFlags and SIG_ELEM_INVOCANT) != 0)
            cf.oLex!![sci.oTryGetLexicalIdx("self")] = decontValue

        /* Handle any constraint types (note that they may refer to the parameter by
         * name, so we need to have bound it already). */
        val postConstraints = param.get_attribute_boxed(tc, gcx.Parameter,
            "$!post_constraints", HINT_post_constraints)
        if (postConstraints != null) {
            val numConstraints = postConstraints.elems(tc)
            for (i in 0 until numConstraints) {
                /* Check we meet the constraint. */
                val consType = postConstraints.at_pos_boxed(tc, i)
                val acceptsMeth = Ops.findmethod(consType, "ACCEPTS", tc)
                if (Ops.isconcrete(consType, tc) == 1L && Ops.istype(consType, gcx.Code, tc) != 0L)
                    RakOps.p6capturelex(consType, tc)
                when (flag) {
                    CallSiteDescriptor.ARG_INT.toInt() ->
                        Ops.invokeDirect(tc, acceptsMeth,
                            ACCEPTS_i, arrayOf<Any?>(consType, arg_i))
                    CallSiteDescriptor.ARG_UINT.toInt() ->
                        Ops.invokeDirect(tc, acceptsMeth,
                            ACCEPTS_u, arrayOf<Any?>(consType, arg_i))
                    CallSiteDescriptor.ARG_NUM.toInt() ->
                        Ops.invokeDirect(tc, acceptsMeth,
                            ACCEPTS_n, arrayOf<Any?>(consType, arg_n))
                    CallSiteDescriptor.ARG_STR.toInt() ->
                        Ops.invokeDirect(tc, acceptsMeth,
                            ACCEPTS_s, arrayOf<Any?>(consType, arg_s))
                    else ->
                        Ops.invokeDirect(tc, acceptsMeth,
                            ACCEPTS_o, arrayOf<Any?>(consType, arg_o))
                }
                if (Ops.istrue(Ops.result_o(tc.curFrame!!), tc) == 0L) {
                    /* Constraint type check failed; produce error if needed. */
                    if (error != null) {
                        val thrower = RakOps.getThrower(tc, "X::TypeCheck::Binding::Parameter")
                        if (thrower != null) {
                            error[0] = thrower
                            error[1] = bindParamThrower
                            error[2] = arrayOf<Any?>(origArg as SixModelObject?,
                                consType!!.st.WHAT, varName, param, 1L)
                        }
                        else {
                            error[0] = String.format(
                                "Constraint type check failed for parameter '%s'",
                                varName)
                        }
                    }
                    return BIND_RESULT_FAIL
                }
            }
        }

        /* TODO: attributives. */
        if ((paramFlags and SIG_ELEM_BIND_ATTRIBUTIVE) != 0) {
            if (flag != CallSiteDescriptor.ARG_OBJ.toInt()) {
                if (error != null)
                    error[0] = "Native attributive binding not yet implemented"
                return BIND_RESULT_FAIL
            }
            val result = assignAttributive(tc, cf, varName, paramFlags,
                param.get_attribute_boxed(tc, gcx.Parameter, "$!attr_package", HINT_attr_package)!!,
                decontValue, error)
            if (result != BIND_RESULT_OK)
                return result
        }

        /* If it has a sub-signature, bind that. */
        val subSignature = param.get_attribute_boxed(tc, gcx.Parameter,
            "$!sub_signature", HINT_sub_signature)
        if (subSignature != null && flag == CallSiteDescriptor.ARG_OBJ.toInt()) {
            /* Turn value into a capture, unless we already have one. */
            val capture: SixModelObject?
            val result: Int
            if ((paramFlags and SIG_ELEM_IS_CAPTURE) != 0) {
                capture = decontValue
            }
            else {
                val meth = Ops.findmethodNonFatal(decontValue, "Capture", tc)
                if (meth == null) {
                    if (error != null)
                        error[0] = "Could not turn argument into capture"
                    return BIND_RESULT_FAIL
                }
                Ops.invokeDirect(tc, meth, Ops.invocantCallSite, arrayOf<Any?>(decontValue))
                capture = Ops.result_o(tc.curFrame!!)
            }

            val subParams = subSignature
                .get_attribute_boxed(tc, gcx.Signature, "@!params", HINT_SIG_params)!!
            /* Recurse into signature binder. */
            val subCsd = explodeCapture(tc, gcx, capture)
            result = bind(tc, gcx, cf, subParams, subCsd, tc.flatArgs, noNomTypeCheck, error)
            if (result != BIND_RESULT_OK) {
                if (error != null && error[0] is String) {
                    /* Note in the error message that we're in a sub-signature. */
                    error[0] = "${error[0]} in sub-signature"

                    /* Have we a variable name? (Always true here — preserved
                     * from the Java original, whose varName check was equally
                     * dead after the "<anon>" defaulting above.) */
                    error[0] = "${error[0]} of parameter $varName"
                }
                return BIND_RESULT_FAIL
            }
        }

        if (RakOps.DEBUG_MODE)
            System.err.println("bindOneParam NYFI")

        return BIND_RESULT_OK
    }

    private val exploder = CallSiteDescriptor(byteArrayOf(
        (CallSiteDescriptor.ARG_OBJ.toInt() or CallSiteDescriptor.ARG_FLAT.toInt()).toByte(),
        (CallSiteDescriptor.ARG_OBJ.toInt() or CallSiteDescriptor.ARG_FLAT.toInt() or CallSiteDescriptor.ARG_NAMED.toInt()).toByte()
    ), null)
    @JvmStatic
    fun explodeCapture(tc: ThreadContext, gcx: RakOps.GlobalExt, capture: SixModelObject?): CallSiteDescriptor {
        val theCapture = Ops.decont(capture, tc)!!

        val capType = gcx.Capture
        var list = theCapture.get_attribute_boxed(tc, capType, "@!list", HINT_CAPTURE_list)
        var hash = theCapture.get_attribute_boxed(tc, capType, "%!hash", HINT_CAPTURE_hash)
        if (list == null)
            list = gcx.EMPTYARR
        if (hash == null)
            hash = gcx.EMPTYHASH

        return exploder.explodeFlattening(tc.curFrame!!, arrayOf<Any?>(list, hash))
    }

    private val parameterizeArray = CallSiteDescriptor(
        byteArrayOf(CallSiteDescriptor.ARG_OBJ, CallSiteDescriptor.ARG_OBJ, CallSiteDescriptor.ARG_OBJ), null)
    private val parameterizeHash = CallSiteDescriptor(
        byteArrayOf(CallSiteDescriptor.ARG_OBJ, CallSiteDescriptor.ARG_OBJ,
            CallSiteDescriptor.ARG_OBJ, CallSiteDescriptor.ARG_OBJ
        ), null)

    /* This takes a signature element and either runs the closure to get a default
     * value if there is one, or creates an appropriate undefined-ish thingy. */
    private fun handleOptional(tc: ThreadContext, gcx: RakOps.GlobalExt, flags: Int, param: SixModelObject, cf: CallFrame): SixModelObject? {
        /* Is the "get default from outer" flag set? */
        if ((flags and SIG_ELEM_DEFAULT_FROM_OUTER) != 0) {
            param.get_attribute_native(tc, gcx.Parameter, "$!variable_name", HINT_variable_name)
            val varName = tc.native_s
            var curOuter = cf.outer
            while (curOuter != null) {
                val idx = curOuter.codeRef.staticInfo.oTryGetLexicalIdx(varName!!)
                if (idx != -1)
                    return curOuter.oLex!![idx]
                curOuter = curOuter.outer
            }
            return null
        }

        /* Do we have a default value or value closure? */
        val defaultValue = param.get_attribute_boxed(tc, gcx.Parameter,
            "$!default_value", HINT_default_value)
        if (defaultValue != null) {
            if ((flags and SIG_ELEM_DEFAULT_IS_LITERAL) != 0) {
                return defaultValue
            }
            else {
                /* Thunk; run it to get a value. */
                Ops.invokeArgless(tc, defaultValue)
                return Ops.result_o(tc.curFrame!!)
            }
        }

        /* Otherwise, go by sigil to pick the correct default type of value. */
        else {
            if ((flags and SIG_ELEM_ARRAY_SIGIL) != 0) {
                val paramType = param.get_attribute_boxed(tc, gcx.Parameter, "$!type", HINT_type)
                var defaultType: SixModelObject? = null

                if (paramType === gcx.Positional) {
                    defaultType = gcx.Array
                }
                else {
                    /* TODO: Find clean solution for handling @deprecation
                     * during compiliation of setting. */
                    param.get_attribute_native(tc, gcx.Parameter, "$!variable_name", HINT_variable_name)
                    val varName = tc.native_s
                    if (varName!! == "@deprecation") {
                        val compilingCoreSetting = Ops.getlexdyn("$*COMPILING_CORE_SETTING", tc)
                        if (Ops.isnull(compilingCoreSetting) == 0L)
                            defaultType = gcx.Array
                    }

                    if (defaultType == null) {
                        val ofMeth = Ops.findmethod(paramType, "of", tc)
                        Ops.invokeDirect(tc, ofMeth, Ops.invocantCallSite, arrayOf<Any?>(paramType))
                        val ofType = Ops.result_o(tc.curFrame!!)

                        val arrayHOW = gcx.Array.st.HOW
                        val parameterizeMeth = Ops.findmethod(arrayHOW, "parameterize", tc)
                        Ops.invokeDirect(tc, parameterizeMeth, parameterizeArray, arrayOf<Any?>(arrayHOW, gcx.Array, ofType))
                        defaultType = Ops.result_o(tc.curFrame!!)
                    }
                }

                val res = Ops.create(defaultType, tc)
                return res
            }
            else if ((flags and SIG_ELEM_HASH_SIGIL) != 0) {
                val paramType = param.get_attribute_boxed(tc, gcx.Parameter, "$!type", HINT_type)
                val defaultType: SixModelObject?

                if (paramType === gcx.Associative) {
                    defaultType = gcx.Hash
                }
                else {
                    val ofMeth = Ops.findmethod(paramType, "of", tc)
                    Ops.invokeDirect(tc, ofMeth, Ops.invocantCallSite, arrayOf<Any?>(paramType))
                    val ofType = Ops.result_o(tc.curFrame!!)

                    val keyofMeth = Ops.findmethod(paramType, "keyof", tc)
                    Ops.invokeDirect(tc, keyofMeth, Ops.invocantCallSite, arrayOf<Any?>(paramType))
                    val keyofType = Ops.result_o(tc.curFrame!!)

                    val hashHOW = gcx.Hash.st.HOW
                    val parameterizeMeth = Ops.findmethod(hashHOW, "parameterize", tc)
                    Ops.invokeDirect(tc, parameterizeMeth, parameterizeHash, arrayOf<Any?>(hashHOW, gcx.Hash, ofType, keyofType))
                    defaultType = Ops.result_o(tc.curFrame!!)
                }

                val res = Ops.create(defaultType, tc)
                return res
            }
            else {
                param.get_attribute_native(tc, gcx.Parameter, "$!flags", HINT_flags)
                val paramFlags = tc.native_i.toInt()
                when (paramFlags and SIG_ELEM_NATIVE_VALUE) {
                    SIG_ELEM_NATIVE_INT_VALUE ->
                        return createBox(tc, gcx, 0L, CallSiteDescriptor.ARG_INT.toInt())
                    SIG_ELEM_NATIVE_UINT_VALUE ->
                        return createBox(tc, gcx, 0L, CallSiteDescriptor.ARG_UINT.toInt())
                    SIG_ELEM_NATIVE_NUM_VALUE ->
                        return createBox(tc, gcx, 0.0, CallSiteDescriptor.ARG_NUM.toInt())
                    SIG_ELEM_NATIVE_STR_VALUE ->
                        return createBox(tc, gcx, null, CallSiteDescriptor.ARG_STR.toInt())
                    else -> {
                        /* Do a coercion, if one is needed. */
                        val paramType = param.get_attribute_boxed(tc, gcx.Parameter, "$!type", HINT_type)
                        val HOW = paramType!!.st.HOW
                        val archetypesMeth = Ops.findmethod(HOW, "archetypes", tc)
                        Ops.invokeDirect(tc, archetypesMeth, Ops.invocantCallSite, arrayOf<Any?>(HOW))
                        val Archetypes = Ops.result_o(tc.curFrame!!)
                        val coerciveMeth = Ops.findmethodNonFatal(Archetypes, "coercive", tc)
                        if (coerciveMeth != null) {
                            Ops.invokeDirect(tc, coerciveMeth, Ops.invocantCallSite, arrayOf<Any?>(Archetypes))
                            if (Ops.istrue(Ops.result_o(tc.curFrame!!), tc) == 1L) {
                                val targetTypeMeth = Ops.findmethod(HOW, "target_type", tc)
                                Ops.invokeDirect(tc, targetTypeMeth, targetType, arrayOf<Any?>(HOW, paramType))
                                return Ops.result_o(tc.curFrame!!)
                            }
                        }
                        return paramType
                    }
                }
            }
        }
    }

    /* Takes a signature along with positional and named arguments and binds them
     * into the provided callframe. Returns BIND_RESULT_OK if binding works out,
     * BIND_RESULT_FAIL if there is a failure and BIND_RESULT_JUNCTION if the
     * failure was because of a Junction being passed (meaning we need to auto-thread). */
    private val slurpyFromArgs = CallSiteDescriptor(
        byteArrayOf(CallSiteDescriptor.ARG_OBJ, CallSiteDescriptor.ARG_OBJ), null)

    @JvmStatic
    fun bind(tc: ThreadContext, gcx: RakOps.GlobalExt, cf: CallFrame, params: SixModelObject,
            csd: CallSiteDescriptor, args: Array<Any?>?,
            noNomTypeCheck: Boolean, error: Array<Any?>?): Int {
        var bindFail = BIND_RESULT_OK
        var curPosArg = 0

        /* If we have a |$foo that's followed by slurpies, then we can suppress
         * any future arity checks. */
        var suppressArityFail = false

        /* If we do have some named args, we want to make a clone of the hash
         * to work on. We'll delete stuff from it as we bind, and what we have
         * left over can become the slurpy hash or - if we aren't meant to be
         * taking one - tell us we have a problem. */
        @Suppress("SENSELESS_COMPARISON")
        var namedArgsCopy = if (csd.nameMap == null)
            null
        else
            Object2IntOpenHashMap<String>(csd.nameMap)

        /* Now we'll walk through the signature and go about binding things. */
        val numPosArgs = csd.numPositionals
        val numParams = params.elems(tc)
        for (i in 0 until numParams) {
            /* Get parameter, its flags and any named names. */
            val param = params.at_pos_boxed(tc, i)!!
            param.get_attribute_native(tc, gcx.Parameter, "$!flags", HINT_flags)
            val flags = tc.native_i.toInt()
            val namedNames = param.get_attribute_boxed(tc,
                gcx.Parameter, "@!named_names", HINT_named_names)

            /* Is it looking for us to bind a capture here? */
            if ((flags and SIG_ELEM_IS_CAPTURE) != 0) {
                /* Capture the arguments from this point forwards into a Capture.
                 * Of course, if there's no variable name we can (cheaply) do pretty
                 * much nothing. */
                param.get_attribute_native(tc, gcx.Parameter, "$!variable_name", HINT_variable_name)
                if (tc.native_s == null) {
                    bindFail = BIND_RESULT_OK
                }
                else {
                    val posArgs = gcx.EMPTYARR.clone(tc)
                    for (k in curPosArg until numPosArgs) {
                        when (csd.argFlags[k]) {
                        CallSiteDescriptor.ARG_OBJ ->
                            posArgs.push_boxed(tc, args!![k] as SixModelObject?)
                        CallSiteDescriptor.ARG_INT ->
                            posArgs.push_boxed(tc, RakOps.p6box_i(args!![k] as Long, tc))
                        CallSiteDescriptor.ARG_UINT ->
                            posArgs.push_boxed(tc, RakOps.p6box_u(args!![k] as Long, tc))
                        CallSiteDescriptor.ARG_NUM ->
                            posArgs.push_boxed(tc, RakOps.p6box_n(args!![k] as Double, tc))
                        CallSiteDescriptor.ARG_STR ->
                            posArgs.push_boxed(tc, RakOps.p6box_s(args!![k] as String?, tc))
                        }
                    }
                    val namedArgs = vmHashOfRemainingNameds(tc, gcx, namedArgsCopy, args)

                    val capType = gcx.Capture
                    val capSnap = capType.st.REPR.allocate(tc, capType.st)
                    capSnap.bind_attribute_boxed(tc, capType, "@!list", HINT_CAPTURE_list, posArgs)
                    capSnap.bind_attribute_boxed(tc, capType, "%!hash", HINT_CAPTURE_hash, namedArgs)

                    bindFail = bindOneParam(tc, gcx, cf, param, capSnap, CallSiteDescriptor.ARG_OBJ,
                        noNomTypeCheck, false, error)
                }
                if (bindFail != 0) {
                    return bindFail
                }
                else if (i + 1 == numParams) {
                    /* Since a capture acts as "the ultimate slurpy" in a sense, if
                     * this is the last parameter in the signature we can return
                     * success right off the bat. */
                    return BIND_RESULT_OK
                }
                else {
                    val nextParam = params.at_pos_boxed(tc, i + 1)!!
                    nextParam.get_attribute_native(tc, gcx.Parameter, "$!flags", HINT_flags)
                    if ((tc.native_i.toInt() and (SIG_ELEM_SLURPY_POS or SIG_ELEM_SLURPY_NAMED)) != 0)
                        suppressArityFail = true
                }
            }

            /* Could it be a named slurpy? */
            else if ((flags and SIG_ELEM_SLURPY_NAMED) != 0) {
                val slurpy = vmHashOfRemainingNameds(tc, gcx, namedArgsCopy, args)
                val bindee = gcx.Hash.st.REPR.allocate(tc, gcx.Hash.st)
                bindee.bind_attribute_boxed(tc, gcx.Map, "$!storage",
                    HINT_ENUMMAP_storage, slurpy)
                bindFail = bindOneParam(tc, gcx, cf, param, bindee, CallSiteDescriptor.ARG_OBJ,
                    noNomTypeCheck, true, error)
                if (bindFail != 0)
                    return bindFail

                /* Nullify named arguments hash now we've consumed it, to mark all
                 * is well. */
                namedArgsCopy = null
            }

            /* Otherwise, maybe it's a positional of some kind. */
            else if (namedNames == null) {
                /* Slurpy or LoL-slurpy? */
                if ((flags and (SIG_ELEM_SLURPY_POS or SIG_ELEM_SLURPY_LOL or SIG_ELEM_SLURPY_ONEARG)) != 0) {
                    /* Create Raku array, create VM array of all remaining things,
                     * then store it. */
                    val slurpy = gcx.EMPTYARR.clone(tc)
                    while (curPosArg < numPosArgs) {
                        when (csd.argFlags[curPosArg]) {
                        CallSiteDescriptor.ARG_OBJ ->
                            slurpy.push_boxed(tc, args!![curPosArg] as SixModelObject?)
                        CallSiteDescriptor.ARG_INT ->
                            slurpy.push_boxed(tc, RakOps.p6box_i(args!![curPosArg] as Long, tc))
                        CallSiteDescriptor.ARG_UINT ->
                            slurpy.push_boxed(tc, RakOps.p6box_u(args!![curPosArg] as Long, tc))
                        CallSiteDescriptor.ARG_NUM ->
                            slurpy.push_boxed(tc, RakOps.p6box_n(args!![curPosArg] as Double, tc))
                        CallSiteDescriptor.ARG_STR ->
                            slurpy.push_boxed(tc, RakOps.p6box_s(args!![curPosArg] as String?, tc))
                        }
                        curPosArg++
                    }

                    val slurpyType = if ((flags and SIG_ELEM_IS_RAW) != 0) gcx.List else gcx.Array
                    val sm = Ops.findmethod(slurpyType,
                        if ((flags and SIG_ELEM_SLURPY_ONEARG) != 0) "from-slurpy-onearg"
                        else if ((flags and SIG_ELEM_SLURPY_POS) != 0) "from-slurpy-flat"
                        else "from-slurpy",
                        tc)
                    Ops.invokeDirect(tc, sm, slurpyFromArgs, arrayOf<Any?>(slurpyType, slurpy))
                    val bindee = Ops.result_o(tc.curFrame!!)

                    bindFail = bindOneParam(tc, gcx, cf, param, bindee, CallSiteDescriptor.ARG_OBJ,
                        noNomTypeCheck, false, error)
                    if (bindFail != 0)
                        return bindFail
                }

                /* Otherwise, a positional. */
                else {
                    /* Do we have a value? */
                    if (curPosArg < numPosArgs) {
                        /* Easy - just bind that. */
                        bindFail = bindOneParam(tc, gcx, cf, param, args!![curPosArg],
                            csd.argFlags[curPosArg], noNomTypeCheck, false, error)
                        if (bindFail != 0)
                            return bindFail
                        curPosArg++
                    }
                    else {
                        /* No value. If it's optional, fetch a default and bind that;
                         * if not, we're screwed. Note that we never nominal type check
                         * an optional with no value passed. */
                        if ((flags and SIG_ELEM_IS_OPTIONAL) != 0) {
                            bindFail = bindOneParam(tc, gcx, cf, param,
                                handleOptional(tc, gcx, flags, param, cf),
                                CallSiteDescriptor.ARG_OBJ, false, false, error)
                            if (bindFail != 0)
                                return bindFail
                        }
                        else {
                            if (error != null)
                                error[0] = arityFail(tc, gcx, cf, params, numParams.toInt(), numPosArgs, false)
                            return BIND_RESULT_FAIL
                        }
                    }
                }
            }

            /* Else, it's a non-slurpy named. */
            else {
                /* Try and get hold of value. */
                var lookup = -1
                if (namedArgsCopy != null) {
                    val numNames = namedNames.elems(tc)
                    for (j in 0 until numNames) {
                        namedNames.at_pos_native(tc, j)
                        val name = tc.native_s
                        if (namedArgsCopy.containsKey(name)) {
                            lookup = namedArgsCopy.removeInt(name)
                            break
                        }
                    }
                }

                /* Did we get one? */
                if (lookup == -1) {
                    /* Nope. We'd better hope this param was optional... */
                    if ((flags and SIG_ELEM_IS_OPTIONAL) != 0) {
                        bindFail = bindOneParam(tc, gcx, cf, param,
                            handleOptional(tc, gcx, flags, param, cf),
                            CallSiteDescriptor.ARG_OBJ, false, false, error)
                    }
                    else if (!suppressArityFail) {
                        if (error != null) {
                            namedNames.at_pos_native(tc, 0)
                            error[0] = "Required named argument '" +
                                tc.native_s +
                                "' not passed"
                        }
                        return BIND_RESULT_FAIL
                    }
                }
                else {
                    bindFail = bindOneParam(tc, gcx, cf, param, args!![lookup shr 6],
                        (lookup and 7).toByte(), noNomTypeCheck, false, error)
                }

                /* If we got a binding failure, return it. */
                if (bindFail != 0)
                    return bindFail
            }
        }

        /* Do we have any left-over args? */
        if (curPosArg < numPosArgs && !suppressArityFail) {
            /* Oh noes, too many positionals passed. */
            if (error != null)
                error[0] = arityFail(tc, gcx, cf, params, numParams.toInt(), numPosArgs, true)
            return BIND_RESULT_FAIL
        }
        if (namedArgsCopy != null && namedArgsCopy.size > 0) {
            /* Oh noes, unexpected named args. */
            if (error != null) {
                val numExtra = namedArgsCopy.size
                if (numExtra == 1) {
                    for (name in namedArgsCopy.keys) {
                        error[0] = "Unexpected named argument '$name' passed"
                    }
                }
                else {
                    var first = true
                    error[0] = "$numExtra unexpected named arguments passed ("
                    for (name in namedArgsCopy.keys) {
                        if (!first)
                            error[0] = "${error[0]}, "
                        else
                            first = false
                        error[0] = "${error[0]}$name"
                    }
                    error[0] = "${error[0]})"
                }
            }
            return BIND_RESULT_FAIL
        }

        /* If we get here, we're done. */
        return BIND_RESULT_OK
    }

    /* Takes any nameds we didn't capture yet and makes a VM Hash of them. */
    private fun vmHashOfRemainingNameds(tc: ThreadContext, gcx: RakOps.GlobalExt, namedArgsCopy: Object2IntOpenHashMap<String>?, args: Array<Any?>?): SixModelObject {
        var slurpy: SixModelObject = gcx.Mu
        if (namedArgsCopy != null) {
            val BOOTHash = tc.gc.BOOTHash!!
            slurpy = BOOTHash.st.REPR.allocate(tc, BOOTHash.st)
            for (name in namedArgsCopy.keys) {
                val lookup = namedArgsCopy.getInt(name)
                when ((lookup and 7).toByte()) {
                CallSiteDescriptor.ARG_OBJ ->
                    slurpy.bind_key_boxed(tc, name, args!![lookup shr 6] as SixModelObject?)
                CallSiteDescriptor.ARG_INT ->
                    slurpy.bind_key_boxed(tc, name, RakOps.p6box_i(args!![lookup shr 6] as Long, tc))
                CallSiteDescriptor.ARG_UINT ->
                    slurpy.bind_key_boxed(tc, name, RakOps.p6box_u(args!![lookup shr 6] as Long, tc))
                CallSiteDescriptor.ARG_NUM ->
                    slurpy.bind_key_boxed(tc, name, RakOps.p6box_n(args!![lookup shr 6] as Double, tc))
                CallSiteDescriptor.ARG_STR ->
                    slurpy.bind_key_boxed(tc, name, RakOps.p6box_s(args!![lookup shr 6] as String?, tc))
                }
            }
        }
        return slurpy
    }
}
