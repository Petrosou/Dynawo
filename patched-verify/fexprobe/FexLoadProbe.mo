model FexLoadProbe "Load whose share is Dynawo's RectifierRegulationCharacteristic FEX block (from the library), driven by the bus voltage"
  extends Dynawo.Electrical.Loads.BaseClasses.BaseLoad;

  Dynawo.Electrical.Controls.Machines.VoltageRegulators.Standard.BaseClasses.RectifierRegulationCharacteristic fex "The real library block, so the on-the-fly compile uses the installed (possibly patched) source";

  Real u "Continuous SISO input of the characteristic (here the bus voltage)";
  Real y "FEX rectifier regulation factor, documented as a [0,1] de-rating fraction";

equation
  fex.u = u;
  y = fex.y;

  if (running.value) then
    u = UPu.value;
    PPu = PRefPu * (1 + deltaP) * y;
    QPu = QRefPu * (1 + deltaQ) * y;
  else
    terminal.i = Complex(0, 0);
    u = 0;
  end if;

  annotation(preferredView = "text");
end FexLoadProbe;
