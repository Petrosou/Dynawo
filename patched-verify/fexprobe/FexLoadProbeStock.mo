model FexLoadProbeStock "Load whose share is the verbatim Dynawo RectifierRegulationCharacteristic FEX tree, driven by the bus voltage"
  extends Dynawo.Electrical.Loads.BaseClasses.BaseLoad;

  parameter Real UHigh = 0.75 "Upper limit of non-linear mode";
  parameter Real ULow = sqrt(3) / 4 "Lower limit of non-linear mode";

  final parameter Real A1 = if ULow == 0 then 0 else (1 - sqrt(UHigh - ULow ^ 2)) / ULow;
  final parameter Real A2 = if UHigh == 1 then 0 else sqrt(UHigh / (1 - UHigh));

  Real u "Continuous SISO input of the characteristic (here the bus voltage)";
  Real y "FEX rectifier regulation factor, documented as a [0,1] de-rating fraction";

equation
  if (running.value) then
    u = UPu.value;

    // verbatim from Dynawo/Electrical/Controls/Machines/VoltageRegulators/Standard/BaseClasses/RectifierRegulationCharacteristic.mo
    if u <= 0 then
      y = 1;
    elseif u > 0 and u <= ULow then
      y = 1 - A1 * u;
    elseif u > ULow and u < UHigh then
      y = sqrt(UHigh - u ^ 2);
    elseif u >= UHigh and u <= 1 then
      y = A2 * (1 - u);
    else
      y = 0;
    end if;

    PPu = PRefPu * (1 + deltaP) * y;
    QPu = QRefPu * (1 + deltaQ) * y;
  else
    terminal.i = Complex(0, 0);
    u = 0;
    y = 0;
  end if;

  annotation(preferredView = "text");
end FexLoadProbeStock;
