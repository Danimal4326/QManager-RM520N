import { Badge } from "@/components/ui/badge";

export function ServiceStatusBadge({
  status,
  installed = true,
}: {
  status: string;
  installed?: boolean;
}) {
  if (status === "running") {
    return (
      <Badge
        variant="outline"
        className="border-success/30 bg-success/10 text-success"
      >
        <span className="mr-1.5 h-1.5 w-1.5 rounded-full bg-success" />
        Active
      </Badge>
    );
  }
  return (
    <Badge
      variant="outline"
      className="border-muted-foreground/30 bg-muted/50 text-muted-foreground"
    >
      <span className="mr-1.5 h-1.5 w-1.5 rounded-full bg-muted-foreground" />
      {installed ? "Inactive" : "Not Installed"}
    </Badge>
  );
}
