import { RefreshCcwIcon, ScanSearchIcon } from "lucide-react";

import { Button } from "@/components/ui/button";
import {
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";

interface ScannerEmptyViewProps {
  onStartScan?: () => void;
}

const ScannerEmptyView = ({ onStartScan }: ScannerEmptyViewProps) => {
  return (
    <Empty className="from-muted/50 to-background h-full bg-linear-to-b from-30%">
      <EmptyHeader>
        <EmptyMedia variant="icon">
          <ScanSearchIcon />
        </EmptyMedia>
        <EmptyTitle>No Scan Results</EmptyTitle>
        <EmptyDescription>
          Discover nearby towers across all carriers and bands.
        </EmptyDescription>
      </EmptyHeader>
      <EmptyContent>
        <Button onClick={onStartScan}>
          <RefreshCcwIcon />
          Start New Scan
        </Button>
      </EmptyContent>
    </Empty>
  );
};

export default ScannerEmptyView;
