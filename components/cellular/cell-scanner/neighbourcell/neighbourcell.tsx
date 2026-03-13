import React from "react";
import NeighbourCellScanner from "./neighbour-scanner";

const NeighbourcellComponent = () => {
  return (
    <div className="@container/main mx-auto p-2">
      <div className="mb-6">
        <h1 className="text-3xl font-bold mb-2">Neighbor Cell Scanner</h1>
        <p className="text-muted-foreground">
          Analyze neighboring towers visible from the current serving cell.
        </p>
      </div>
      <NeighbourCellScanner />
    </div>
  );
};

export default NeighbourcellComponent;
