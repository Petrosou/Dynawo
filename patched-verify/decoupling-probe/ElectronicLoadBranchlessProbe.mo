model ElectronicLoadBranchlessProbe "Branchless ElectronicLoad with an independent UMinPu start parameter (round-6 decoupling probe)"
  extends Dynawo.Electrical.Loads.BaseClasses.BaseLoad;

  parameter Dynawo.Types.VoltageModulePu Ud1Pu "Voltage at which the load starts to disconnect in pu (base UNom)";
  parameter Dynawo.Types.VoltageModulePu Ud2Pu "Voltage at which the load is completely disconnected in pu (base UNom)";
  parameter Real recoveringShare "Share of the load that recovers from low voltage trip";
  parameter Dynawo.Types.Time tFilter = 1e-2 "Time constant for estimation of UMinPu in s";
  parameter Dynawo.Types.VoltageModulePu UMin0Pu "Independent start value for UMinPu (the probe variable)";

  Dynawo.Types.VoltageModulePu UMinPu(start = UMin0Pu) "Minimum voltage during the simulation in pu (base UNom)";
  Real connectedShare(start = 1) "Share of the load that is currently connected";

equation
  assert(recoveringShare >= 0 and recoveringShare <= 1, "recoveringShare must be within [0,1]");

  if (running.value) then
    UMinPu + tFilter * der(UMinPu) = if (UPu.value < UMinPu and UMinPu > Ud2Pu) then UPu.value else UMinPu;

    connectedShare = noEvent(
        min(1, max(0, (min(UPu.value, UMinPu) - Ud2Pu) / (Ud1Pu - Ud2Pu)))
        + recoveringShare * (
            min(1, max(0, (UPu.value - Ud2Pu) / (Ud1Pu - Ud2Pu)))
            - min(1, max(0, (min(UPu.value, UMinPu) - Ud2Pu) / (Ud1Pu - Ud2Pu)))));

    PPu = PRefPu * (1 + deltaP) * connectedShare;
    QPu = QRefPu * (1 + deltaQ) * connectedShare;
  else
    terminal.i = Complex(0, 0);
    connectedShare = 0;
    UMinPu = Ud2Pu;
  end if;

  annotation(preferredView = "text");
end ElectronicLoadBranchlessProbe;
