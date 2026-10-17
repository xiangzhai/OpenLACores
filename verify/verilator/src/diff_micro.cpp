// ------------------------------------------------------------------------------------//
//  Copyright (c) 2026 Loongson Technology Corporation Limited.
//
//  OpenLACores is licensed under Mulan PSL v2.
// 
//  You can use this software according to the terms and conditions of the Mulan PSL v2.
//
//  You may obtain a copy of Mulan PSL v2 at:
//           http://license.coscl.org.cn/MulanPSL2
// 
//  THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY
//  KIND, EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO
//  NON-INFRINGEMENT, MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// 
//  See the Mulan PSL v2 for more details.
// ------------------------------------------------------------------------------------//

#include "Vverilator_top.h"
#include "Vverilator_top___024root.h"
#include "sim.h"
#include "verilated_save.h"
#include <iomanip>
#include <sstream>
#include <stdexcept>
#include <utility>

namespace openla132::sim {
namespace {

// Identifies a CPUCFG instruction encoding.
bool is_cpucfg(uint32_t inst) {
  return (inst & 0xfffffc00U) == 0x00006c00U;
}

// Identifies an rdtime instruction micro-operation.
bool is_rdtime(uint32_t inst) {
  uint32_t opcode = inst & 0xfffffc00U;
  return opcode == 0x00006000U || opcode == 0x00006400U;
}

// Identifies a CSR instruction accessing the debug CSR range.
bool is_debug_csr(uint32_t inst) {
  if ((inst & 0xff000000U) != 0x04000000U) {
    return false;
  }
  uint32_t csr = (inst >> 10U) & 0x3fffU;
  return csr >= 0x300U && csr <= 0x3ffU;
}

// Identifies the LA132 user-defined control CSR. The reference model does
// not implement it, so any GPR result from csrrd/csrwr/csrxchg is taken from
// the DUT instead of being compared against the reference.
bool is_userdef_csr(uint32_t inst) {
  if ((inst & 0xff000000U) != 0x04000000U) {
    return false;
  }
  return ((inst >> 10U) & 0x3fffU) == 0x0afU;
}

constexpr std::array<uint32_t, 23> extra_csrs = {
  0x1cU, 0x1dU, 0x1eU, 0x1fU, 0x21U, 0x22U, 0x23U, 0x43U, 0x80U, 0x81U, 0x89U, 0x8aU,
  0x8bU, 0x8cU, 0x8dU, 0x8eU, 0x8fU, 0x90U, 0x91U, 0x92U, 0x93U, 0x94U, 0x95U,
};

// Serializes the RTL exception and interrupt state used by difftest.
void save_state(VerilatedSerialize &out, const DiffState &state) {
  out << state.int_entry << state.crmd << state.prmd << state.ecfg << state.estat << state.era << state.badv
      << state.eentry << state.tval << state.int_taken;
}

// Restores the RTL exception and interrupt state used by difftest.
void load_state(VerilatedDeserialize &in, DiffState &state) {
  in >> state.int_entry >> state.crmd >> state.prmd >> state.ecfg >> state.estat >> state.era >> state.badv >>
      state.eentry >> state.tval >> state.int_taken;
}

class La132Diff final : public DiffMicro {
public:
  // Samples RTL exceptions and decoded instructions.
  void sample(const Vverilator_top &top) override {
    const Vverilator_top___024root *root = top.rootp;
    if (top.ex_taken) {
      trap_seen = true;
      trap_entry = top.ex_entry;
    }

    if (!root->verilator_top__DOT__x_open132_ip_top__DOT__x_la132_core__DOT__x_dsu_stage__DOT__valid) {
      return;
    }

    uint32_t pc = root->verilator_top__DOT__x_open132_ip_top__DOT__x_la132_core__DOT__x_dsu_stage__DOT__pc;
    uint32_t inst = root->verilator_top__DOT__x_open132_ip_top__DOT__x_la132_core__DOT__x_dsu_stage__DOT__inst;
    if (!decoded.empty() && decoded.back().first == pc && decoded.back().second == inst) {
      return;
    }
    decoded.emplace_back(pc, inst);
    if (decoded.size() > 32) {
      decoded.pop_front();
    }
  }

  // Detects whether the current commit accesses UART MMIO.
  bool is_mmio(const Vverilator_top &top) const override {
    const Vverilator_top___024root *root = top.rootp;
    bool valid = top.lsu_mem_valid;
    bool load = top.lsu_mem_load;
    bool store = top.lsu_mem_store;
    uint32_t addr = top.commit_mem_addr;
    return valid && (load || store) && addr >= UART_BASE && addr < UART_BASE + 0x100U;
  }

  // Returns the decoded instruction for a committed PC when available.
  uint32_t instruction(uint32_t pc, uint32_t fallback) const override {
    for (auto item = decoded.rbegin(); item != decoded.rend(); ++item) {
      if (item->first == pc) {
        return item->second;
      }
    }
    return fallback;
  }

  // Initializes the reference model with LA132 reset CSR values.
  void init(Ref &ref, uint32_t pc) override {
    ref.set_csr(0xcU, pc);
    ref.set_csr(0x21U, 0x001f71f2U);
    ref.set_csr(0x22U, 0x00001000U);
    ref.set_csr(0x23U, 0x00000071U);
    ref.set_csr(0x1cU, 0U);
    ref.set_csr(0x1dU, 0U);
    ref.set_csr(0x1eU, 0U);
    ref.set_csr(0x80U, 0x80U);
    ref.set_csr(0x93U, pc);
  }

  // Records the latest RTL exception and interrupt state.
  void observe(const DiffState &new_state) override {
    state = new_state;
    if (trap_seen) {
      irq = new_state;
      irq.int_taken = true;
      irq.int_entry = trap_entry;
      irq_pending = true;
      trap_seen = false;
    } else if (new_state.int_taken) {
      irq = new_state;
      irq_pending = true;
    }
  }

  // Synchronizes asynchronous RTL CSR state into the reference model.
  void sync(Ref &ref, la_ref_state_t &regs) override {
    if (regs.csr.tval != state.tval) {
      regs.csr.tval = state.tval;
      ref.set_csr(0x42U, regs.csr.tval);
    }

    constexpr uint64_t pending_mask = (0xffULL << 2U) | (1ULL << 11U);
    uint64_t estat = (regs.csr.estat & ~pending_mask) | (state.estat & pending_mask);
    if (regs.csr.estat != estat) {
      regs.csr.estat = estat;
      ref.set_csr(0x5U, estat, pending_mask);
    }
  }

  // Fixes the reference PC when a pending RTL exception or interrupt is taken.
  bool fix_pc(const Commit &commit, Ref &ref, la_ref_state_t &regs) override {
    if (!irq_pending || commit.pc != irq.int_entry) {
      return false;
    }
    take_irq(ref, regs);
    return true;
  }

  // Handles the two-micro-operation rdtime execution sequence.
  DiffAction before_exec(const Commit &commit, const std::array<uint32_t, 32> &, std::string &error) override {
    if (rdtime_pending) {
      if (commit.pc != rdtime_pc || !is_rdtime(commit.inst)) {
        std::ostringstream out;
        out << "missing second rdtime micro-op: first PC=0x" << std::hex << std::setw(8) << std::setfill('0')
            << rdtime_pc << " next PC=0x" << std::setw(8) << commit.pc;
        error = out.str();
        return DiffAction::Fail;
      }
      rdtime_second = true;
      return DiffAction::Exec;
    }

    if (!is_rdtime(commit.inst)) {
      return DiffAction::Exec;
    }

    rdtime_pc = commit.pc;
    rdtime_rd = static_cast<uint8_t>(commit.inst & 0x1fU);
    rdtime_rj = static_cast<uint8_t>((commit.inst >> 5U) & 0x1fU);
    rdtime_pending = true;
    return DiffAction::Skip;
  }

  // Reconciles known LA132 and reference-model execution differences.
  void after_exec(const Commit &commit, const std::array<uint32_t, 32> &gpr, Ref &ref, la_ref_state_t &regs) override {
    bool changed = false;
    if (rdtime_second) {
      regs.xrf.value[rdtime_rd] = gpr[rdtime_rd];
      regs.xrf.value[rdtime_rj] = gpr[rdtime_rj];
      rdtime_pending = false;
      rdtime_second = false;
      changed = true;
    } else if ((is_cpucfg(commit.inst) || is_debug_csr(commit.inst) || is_userdef_csr(commit.inst)) && commit.wen && commit.wdest) {
      regs.xrf.value[commit.wdest] = commit.wdata;
      changed = true;
    }

    if (irq_pending) {
      for (size_t index = 0; index < gpr.size(); index++) {
        regs.xrf.value[index] = gpr[index];
      }
      changed = true;
    }
    if (changed) {
      ref.set_regs(regs);
    }
  }

  // Injects a pending exception or interrupt after a committed instruction.
  void after_commit(Ref &ref, la_ref_state_t &regs) override {
    if (irq_pending) {
      take_irq(ref, regs);
    }
  }

  // Saves the internal LA132 difftest-policy state.
  void save(VerilatedSerialize &out) const override {
    save_state(out, state);
    save_state(out, irq);
    out << irq_pending << rdtime_pc << rdtime_rd << rdtime_rj << rdtime_pending << rdtime_second;
  }

  // Restores the internal LA132 difftest-policy state.
  void load(VerilatedDeserialize &in) override {
    load_state(in, state);
    load_state(in, irq);
    in >> irq_pending >> rdtime_pc >> rdtime_rd >> rdtime_rj >> rdtime_pending >> rdtime_second;
    trap_seen = false;
    trap_entry = 0;
    decoded.clear();
  }

  // Saves LA132-specific reference CSRs.
  void save_ref(VerilatedSerialize &out, const Ref &ref) const override {
    for (uint32_t csr: extra_csrs) {
      out << ref.get_csr(csr);
    }
  }

  // Restores LA132-specific reference CSRs.
  void load_ref(VerilatedDeserialize &in, Ref &ref) override {
    for (uint32_t csr: extra_csrs) {
      uint64_t value = 0;
      in >> value;
      ref.set_csr(csr, value);
    }
  }

private:
  // Switches the reference model to the observed RTL exception or interrupt state.
  void take_irq(Ref &ref, la_ref_state_t &regs) {
    regs.pc = irq.int_entry;
    regs.csr.crmd = irq.crmd;
    regs.csr.prmd = irq.prmd;
    regs.csr.ecfg = irq.ecfg;
    regs.csr.estat = irq.estat;
    regs.csr.era = irq.era;
    regs.csr.badv = irq.badv;
    regs.csr.eentry = irq.eentry;
    regs.csr.tval = irq.tval;
    ref.set_regs(regs);
    irq_pending = false;
  }

  DiffState state{};
  DiffState irq{};
  bool irq_pending = false;
  bool trap_seen = false;
  uint32_t trap_entry = 0;
  uint32_t rdtime_pc = 0;
  uint8_t rdtime_rd = 0;
  uint8_t rdtime_rj = 0;
  bool rdtime_pending = false;
  bool rdtime_second = false;
  std::deque<std::pair<uint32_t, uint32_t>> decoded;
};

} // namespace

// Creates the microarchitectural difftest policy selected by CPU model name.
std::unique_ptr<DiffMicro> make_diff_micro(const std::string &cpu) {
  if (cpu == "la132" || cpu == "openla132") {
    return std::make_unique<La132Diff>();
  }
  throw std::runtime_error("unsupported DiffTest CPU model: " + cpu);
}

} // namespace openla132::sim
