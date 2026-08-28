// CONTRIBUTED MODEL — NOT INSTALLED. Origin: the independent AI review
// chain (round-5 relay), offered under MPL-2.0. This composite model
// embeds the branchless share law, whose SolverIDA voltage-step
// regression (patched-verify/step-into-band/) is unresolved; adoption is
// deferred until the law question settles. Registration notes from the
// relay: needs an .extvar copied from ElectronicLoad.extvar beside the
// .mo, a package.order entry after ElectronicLoad, and a preassembled
// descriptor patterned on ElectronicLoad.xml with
// initName="Dynawo.Electrical.Loads.Load_INIT". See bug128/SWEEP.md
// round 5.

within Dynawo.Electrical.Loads;

model ElectronicLoadAlphaBeta "Alpha-beta load with frozen-impedance continuation below UBreakPu and a latched WECC partial-trip share on the whole load"
  extends BaseClasses.BaseLoad;
  extends AdditionalIcons.Load;

  parameter Real alpha "Active load sensitivity to voltage";
  parameter Real beta "Reactive load sensitivity to voltage";
  parameter Types.VoltageModulePu UBreakPu "Law-argument floor in pu (base UNom); below it the law freezes to constant impedance";
  parameter Types.VoltageModulePu Ud1Pu "Voltage at which the participating share starts to disconnect in pu (base UNom)";
  parameter Types.VoltageModulePu Ud2Pu "Voltage at which the participating share is completely disconnected in pu (base UNom)";
  parameter Real recoveringShare "Share of the tripped load that recovers from low voltage trip";
  parameter Real fShare "Participating fraction of the load: F = 1 - fShare + fShare*connectedShare multiplies P and Q alike";
  parameter Types.Time tFilter = 1e-2 "Time constant for estimation of UMinPu in s";

  Types.VoltageModulePu UMinPu(start = max(ComplexMath.'abs'(u0Pu), Ud2Pu)) "Minimum voltage during the simulation (with lower bound at Ud2Pu) in pu (base UNom)";
  Real connectedShare(start = 1) "Connected fraction of the participating share (the WECC Fwecc)";
  Types.VoltageModulePu UEffPu(start = max(ComplexMath.'abs'(u0Pu), UBreakPu)) "Law argument: terminal voltage floored at UBreakPu in pu (base UNom)";

equation
  assert(recoveringShare >= 0 and recoveringShare <= 1, "recoveringShare must be within [0,1]");
  assert(fShare > 0 and fShare <= 1, "fShare must be within (0,1]");
  assert(Ud1Pu > Ud2Pu, "Ud1Pu must be greater than Ud2Pu");

  if (running.value) then
    UMinPu + tFilter * der(UMinPu) = if (UPu.value < UMinPu and UMinPu > Ud2Pu) then UPu.value else UMinPu;

    // Branchless share law (see ElectronicLoadBranchless.mo): with
    // down(x) = min(1, max(0, (x - Ud2Pu)/(Ud1Pu - Ud2Pu))) and
    // m = min(UPu, UMinPu), connectedShare = down(m) + recoveringShare*(down(UPu) - down(m)).
    connectedShare = noEvent(
        min(1, max(0, (min(UPu.value, UMinPu) - Ud2Pu) / (Ud1Pu - Ud2Pu)))
        + recoveringShare * (
            min(1, max(0, (UPu.value - Ud2Pu) / (Ud1Pu - Ud2Pu)))
            - min(1, max(0, (min(UPu.value, UMinPu) - Ud2Pu) / (Ud1Pu - Ud2Pu)))));

    UEffPu = noEvent(max(UPu.value, UBreakPu));

    PPu = PRefPu * (1 + deltaP) * ((UEffPu / ComplexMath.'abs'(u0Pu)) ^ alpha)
          * (UPu.value / UEffPu) ^ 2
          * (1 - fShare + fShare * connectedShare);
    QPu = QRefPu * (1 + deltaQ) * ((UEffPu / ComplexMath.'abs'(u0Pu)) ^ beta)
          * (UPu.value / UEffPu) ^ 2
          * (1 - fShare + fShare * connectedShare);
  else
    terminal.i = Complex(0);
    connectedShare = 0;
    UMinPu = Ud2Pu;
    UEffPu = UBreakPu;
  end if;

  annotation(preferredView = "text");
end ElectronicLoadAlphaBeta;
