import React from "react";
import FullScannerComponent from "./scanner";

const CellScannerComponent = () => {
  return (
    <div className="@container/main mx-auto p-2">
      <div className="mb-6">
        <h1 className="text-3xl font-bold mb-2">Cell Scanner</h1>
        <p className="text-muted-foreground">
          Scan nearby towers across all carriers. Best results without an
          active SIM.
        </p>
      </div>
      <FullScannerComponent />
    </div>
  );
};

export default CellScannerComponent;
