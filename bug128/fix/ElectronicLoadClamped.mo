model ElectronicLoadClamped "Dynawo v1.7.0 ElectronicLoad with connectedShare expressions clamped to [0,1] (candidate fix)"
  extends Dynawo.Electrical.Loads.BaseClasses.BaseLoad;

  parameter Dynawo.Types.VoltageModulePu Ud1Pu "Voltage at which the load starts to disconnect in pu (base UNom)";
  parameter Dynawo.Types.VoltageModulePu Ud2Pu "Voltage at which the load is completely disconnected in pu (base UNom)";
  parameter Real recoveringShare "Share of the load that recovers from low voltage trip";
  parameter Dynawo.Types.Time tFilter = 1e-2 "Time constant for estimation of UMinPu in s";

  Dynawo.Types.VoltageModulePu UMinPu(start = Modelica.ComplexMath.'abs'(u0Pu)) "Minimum voltage during the simulation (with lower bound at Ud2Pu) in pu (base UNom)";
  Real connectedShare(start = 1) "Share of the load that is currently connected";

equation
  if (running.value) then
    UMinPu + tFilter * der(UMinPu) = if (UPu.value < UMinPu and UMinPu > Ud2Pu) then UPu.value else UMinPu;

    if UPu.value < Ud2Pu then
      connectedShare = 0;
    elseif UPu.value < Ud1Pu then
      if UPu.value <= UMinPu then  // Voltage currently decreasing (below UMinPu)
        connectedShare = min(1, max(0, (UPu.value - Ud2Pu) / (Ud1Pu - Ud2Pu)));
      else  // Voltage recovering, so partial reconnection
        connectedShare = min(1, max(0, ((UMinPu - Ud2Pu) + recoveringShare * (UPu.value - UMinPu)) / (Ud1Pu - Ud2Pu)));
      end if;
    else
      if UMinPu >= Ud1Pu then  // Voltage never dropped below Ud1Pu
        connectedShare = 1;
      else
        connectedShare = min(1, max(0, ((UMinPu - Ud2Pu) + recoveringShare * (Ud1Pu - UMinPu)) / (Ud1Pu - Ud2Pu)));
      end if;
    end if;

    PPu = PRefPu * (1 + deltaP) * connectedShare;
    QPu = QRefPu * (1 + deltaQ) * connectedShare;
  else
    terminal.i = Complex(0, 0);
    connectedShare = 0;
    UMinPu = 0;
  end if;

  annotation(preferredView = "text");
end ElectronicLoadClamped;
