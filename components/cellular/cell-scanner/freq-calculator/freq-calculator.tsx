import React from "react";
import FrequencyCalculator from "./calculator";

const FrequencyCalculatorComponent = () => {
  return (
    <div className="@container/main mx-auto p-2">
      <div className="mb-6">
        <h1 className="text-3xl font-bold mb-2">Frequency Calculator</h1>
        <p className="text-muted-foreground">
          Convert between EARFCN/NR-ARFCN, frequency, and band for LTE and
          5G NR.
        </p>
      </div>
      <FrequencyCalculator />
    </div>
  );
};

export default FrequencyCalculatorComponent;
