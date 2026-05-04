"use client";

import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import TestRow from "./test-row";
import {
  CATEGORY_LABELS,
  CATEGORY_DESCRIPTIONS,
  type HealthCheckTest,
  type TestCategory,
} from "@/types/system-health-check";

interface CategoryCardProps {
  category: TestCategory;
  tests: HealthCheckTest[];
  fetchOutput: (testId: string) => Promise<string>;
}

export default function CategoryCard({ category, tests, fetchOutput }: CategoryCardProps) {
  return (
    <Card className="h-full">
      <CardHeader>
        <CardTitle>{CATEGORY_LABELS[category]}</CardTitle>
        <CardDescription>{CATEGORY_DESCRIPTIONS[category]}</CardDescription>
      </CardHeader>
      <CardContent>
        <div className="divide-y">
          {tests.map((t) => (
            <TestRow key={t.id} test={t} fetchOutput={fetchOutput} />
          ))}
        </div>
      </CardContent>
    </Card>
  );
}
