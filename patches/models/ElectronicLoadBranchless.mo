// CONTRIBUTED MODEL — NOT INSTALLED BY apply_model_patches.py.
// Origin: the independent AI review chain (round-5 relay), offered under
// MPL-2.0. Status: verified algebraically identical to the installed
// clamped ladder (patched-verify/test_branchless_identity.py: 14.5M float
// points at one ulp, 200k exact-rational points at zero mismatches, on
// UMinPu >= Ud2Pu), removes all four share zero-crossing relations from
// the compiled model, removes the mode-frozen clearing-instant sample,
// and per the relaying chain fixes a fault-application restoration kill
// at high electronic share. NOT adopted because it regresses SolverIDA
// on voltage steps landing inside the share band (verified counterexample
// in patched-verify/step-into-band/). See bug128/SWEEP.md round 5.

within Dynawo.Electrical.Loads;

model ElectronicLoad "Constant power load with disconnection and reconnections depending on the voltage"
  extends BaseClasses.BaseLoad;
  extends AdditionalIcons.Load;

  parameter Types.VoltageModulePu Ud1Pu "Voltage at which the load starts to disconnect in pu (base UNom)";
  parameter Types.VoltageModulePu Ud2Pu "Voltage at which the load is completely disconnected in pu (base UNom)";
  parameter Real recoveringShare "Share of the load that recovers from low voltage trip";
  parameter Types.Time tFilter = 1e-2 "Time constant for estimation of UMinPu in s";

  Types.VoltageModulePu UMinPu(start = max(ComplexMath.'abs'(u0Pu), Ud2Pu)) "Minimum voltage during the simulation (with lower bound at Ud2Pu) in pu (base UNom)";
  Real connectedShare(start = 1) "Share of the load that is currently connected";

equation
  assert(recoveringShare >= 0 and recoveringShare <= 1, "recoveringShare must be within [0,1]");

  if (running.value) then
    UMinPu + tFilter * der(UMinPu) = if (UPu.value < UMinPu and UMinPu > Ud2Pu) then UPu.value else UMinPu;

    // Branchless share law: with down(x) = min(1, max(0, (x - Ud2Pu)/(Ud1Pu - Ud2Pu)))
    // and m = min(UPu, UMinPu),
    //   connectedShare = down(m) + recoveringShare * (down(UPu) - down(m))
    // is algebraically identical to the clamped piecewise ladder at every
    // (UPu, UMinPu) with UMinPu >= Ud2Pu (the filter's invariant), so the
    // share is a single continuous expression: an event restoration that
    // holds branch selections frozen evaluates the same function as the
    // unfrozen law, and there is no stale-branch value to propagate.
    connectedShare = noEvent(
        min(1, max(0, (min(UPu.value, UMinPu) - Ud2Pu) / (Ud1Pu - Ud2Pu)))
        + recoveringShare * (
            min(1, max(0, (UPu.value - Ud2Pu) / (Ud1Pu - Ud2Pu)))
            - min(1, max(0, (min(UPu.value, UMinPu) - Ud2Pu) / (Ud1Pu - Ud2Pu)))));

    PPu = PRefPu * (1 + deltaP) * connectedShare;
    QPu = QRefPu * (1 + deltaQ) * connectedShare;
  else
    terminal.i = Complex(0);
    connectedShare = 0;
    UMinPu = Ud2Pu;
  end if;

  annotation(preferredView = "text");
end ElectronicLoad;
