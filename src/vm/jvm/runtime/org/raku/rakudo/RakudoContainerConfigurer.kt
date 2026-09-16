package org.raku.rakudo

import org.raku.nqp.runtime.ExceptionHandling
import org.raku.nqp.runtime.ThreadContext
import org.raku.nqp.sixmodel.ContainerConfigurer
import org.raku.nqp.sixmodel.ContainerSpec
import org.raku.nqp.sixmodel.STable
import org.raku.nqp.sixmodel.SixModelObject

class RakudoContainerConfigurer : ContainerConfigurer() {
    override fun newContainerSpec(tc: ThreadContext, st: STable): ContainerSpec = RakudoContainerSpec()

    override fun configureContainerSpec(tc: ThreadContext, cs: ContainerSpec, config: SixModelObject) {
        cs as RakudoContainerSpec
        cs.store = grabOneValue(tc, config, "store")
        cs.storeUnchecked = grabOneValue(tc, config, "store_unchecked")
        cs.cas = grabOneValue(tc, config, "cas")
        cs.atomicStore = grabOneValue(tc, config, "atomic_store")
    }

    private fun grabOneValue(tc: ThreadContext, config: SixModelObject, key: String): SixModelObject {
        return config.at_key_boxed(tc, key)
            ?: throw ExceptionHandling.dieInternal(tc,
                "Container spec must be configured with a '$key'")
    }
}
