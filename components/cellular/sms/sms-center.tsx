"use client";

import React from "react";
import SmsInboxCard from "./sms-inbox-card";
import { useSms } from "@/hooks/use-sms";

const SmsCenterComponent = () => {
  const {
    data,
    isLoading,
    isSaving,
    error,
    sendSms,
    deleteSms,
    deleteAllSms,
    refresh,
  } = useSms();

  return (
    <div className="@container/main mx-auto p-2">
      <div className="grid grid-cols-1 grid-flow-row gap-4">
        <SmsInboxCard
          data={data}
          isLoading={isLoading}
          isSaving={isSaving}
          onSend={sendSms}
          onDelete={deleteSms}
          onDeleteAll={deleteAllSms}
          onRefresh={() => refresh()}
        />
      </div>
    </div>
  );
};

export default SmsCenterComponent;
