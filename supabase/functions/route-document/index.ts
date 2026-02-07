import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

// MARK: - CORS Headers

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

// MARK: - Types

interface RouteRequest {
  scanId: string;
  targetType: "BINDER" | "BILLING" | "HANDOFF" | "INBOX";
  binderItemType?: string;
  overrideFields?: Record<string, unknown>;
}

interface RouteResponse {
  success: boolean;
  targetId?: string;
  targetType?: string;
  attachmentIds?: string[];
  error?: {
    code: string;
    message: string;
  };
}

// MARK: - Routing Configuration

const DOCUMENT_TYPE_ROUTING: Record<
  string,
  { target: string; binderType?: string }
> = {
  PRESCRIPTION: { target: "BINDER", binderType: "MED" },
  LAB_RESULT: { target: "HANDOFF" },
  DISCHARGE: { target: "HANDOFF" },
  BILL: { target: "BILLING" },
  EOB: { target: "BILLING" },
  APPOINTMENT: { target: "BINDER", binderType: "CONTACT" },
  INSURANCE_CARD: { target: "BINDER", binderType: "INSURANCE" },
  MEDICATION_LIST: { target: "BINDER", binderType: "MED" },
  OTHER: { target: "INBOX" },
};

// MARK: - Main Handler

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Get auth header
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "AUTH_INVALID_TOKEN",
            message: "No authorization header",
          },
        } as RouteResponse),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Create Supabase clients
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")!;

    const supabaseUser = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const supabaseService = createClient(supabaseUrl, supabaseServiceKey);

    // Get current user
    const {
      data: { user },
      error: userError,
    } = await supabaseUser.auth.getUser();

    if (userError || !user) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "AUTH_INVALID_TOKEN",
            message: "Invalid or expired token",
          },
        } as RouteResponse),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Parse request body
    const body: RouteRequest = await req.json();
    const { scanId, targetType, binderItemType, overrideFields } = body;

    if (!scanId || !targetType) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "VALIDATION_ERROR",
            message: "Missing scanId or targetType",
          },
        } as RouteResponse),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Validate UUID format for scanId
    const UUID_REGEX =
      /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
    if (!UUID_REGEX.test(scanId)) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "VALIDATION_ERROR",
            message: "Invalid scanId format",
          },
        } as RouteResponse),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Validate target type
    if (!["BINDER", "BILLING", "HANDOFF", "INBOX"].includes(targetType)) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "INVALID_TARGET",
            message: "Invalid target type",
          },
        } as RouteResponse),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Fetch the document scan
    const { data: scan, error: scanError } = await supabaseService
      .from("document_scans")
      .select("*")
      .eq("id", scanId)
      .single();

    if (scanError || !scan) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "INVALID_SCAN",
            message: "Scan not found",
          },
        } as RouteResponse),
        {
          status: 404,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Verify scan is ready for routing
    if (scan.status === "ROUTED") {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "ALREADY_ROUTED",
            message: "Scan has already been routed",
          },
        } as RouteResponse),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Check membership and permissions
    const { data: membership } = await supabaseService
      .from("circle_members")
      .select("role")
      .eq("circle_id", scan.circle_id)
      .eq("user_id", user.id)
      .eq("status", "ACTIVE")
      .single();

    if (!membership || membership.role === "VIEWER") {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "PERMISSION_DENIED",
            message: "Contributors+ required to route documents",
          },
        } as RouteResponse),
        {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Merge extracted fields with overrides
    const extractedFields = scan.extracted_fields_json || {};
    const finalFields = { ...extractedFields, ...overrideFields };

    let targetId: string;
    const attachmentIds: string[] = [];

    // Route based on target type
    switch (targetType) {
      case "BINDER": {
        // Determine binder item type
        const routing = DOCUMENT_TYPE_ROUTING[scan.document_type || "OTHER"];
        const itemType = binderItemType || routing?.binderType || "DOC";

        // Build content JSON based on binder item type
        let contentJson: Record<string, unknown>;
        let title: string;

        switch (itemType) {
          case "MED":
            contentJson = {
              name:
                finalFields.medication ||
                finalFields.medications?.[0]?.name ||
                "Unknown Medication",
              dose:
                finalFields.dosage ||
                finalFields.medications?.[0]?.dosage ||
                "",
              schedule:
                finalFields.frequency ||
                finalFields.medications?.[0]?.frequency ||
                "",
              prescriber: finalFields.prescriber || "",
              pharmacy: finalFields.pharmacy || "",
              notes: `Scanned from document on ${new Date().toLocaleDateString()}`,
            };
            title = contentJson.name as string;
            break;

          case "INSURANCE":
            contentJson = {
              provider: finalFields.insuranceName || "Unknown Insurance",
              plan_name: finalFields.planName || "",
              member_id: finalFields.memberId || "",
              group_number: finalFields.groupNumber || "",
              phone: finalFields.customerServicePhone || "",
              rx_bin: finalFields.rxBin || "",
              rx_pcn: finalFields.rxPcn || "",
              notes: `Scanned from document on ${new Date().toLocaleDateString()}`,
            };
            title = contentJson.provider as string;
            break;

          case "CONTACT":
            contentJson = {
              name: finalFields.provider || "Unknown Provider",
              role: finalFields.specialty || "doctor",
              phone: finalFields.phone || "",
              organization: finalFields.location || "",
              notes:
                finalFields.instructions ||
                `Appointment: ${finalFields.appointmentDate || ""} ${finalFields.appointmentTime || ""}`,
            };
            title = contentJson.name as string;
            break;

          default: // DOC
            contentJson = {
              description: scan.ocr_text?.slice(0, 500) || "Scanned document",
              document_type: scan.document_type?.toLowerCase() || "other",
              date: new Date().toISOString().split("T")[0],
            };
            title = `Scanned ${scan.document_type || "Document"} - ${new Date().toLocaleDateString()}`;
        }

        // Create binder item
        const { data: binderItem, error: binderError } = await supabaseService
          .from("binder_items")
          .insert({
            circle_id: scan.circle_id,
            patient_id: scan.patient_id,
            type: itemType,
            title,
            content_json: contentJson,
            is_active: true,
            created_by: user.id,
            updated_by: user.id,
            source_document_id: scan.id,
          })
          .select("id")
          .single();

        if (binderError || !binderItem) {
          console.error("Failed to create binder item:", binderError);
          throw new Error("Failed to create binder item");
        }

        targetId = binderItem.id;
        break;
      }

      case "BILLING": {
        // Determine financial item kind
        const kind = scan.document_type === "EOB" ? "EOB" : "BILL";

        // Parse amounts
        const parseAmount = (val: unknown): number | null => {
          if (typeof val === "number") return Math.round(val * 100);
          if (typeof val === "string") {
            const num = parseFloat(val.replace(/[$,]/g, ""));
            return isNaN(num) ? null : Math.round(num * 100);
          }
          return null;
        };

        // Create financial item
        const { data: financialItem, error: financialError } =
          await supabaseService
            .from("financial_items")
            .insert({
              circle_id: scan.circle_id,
              patient_id: scan.patient_id,
              created_by: user.id,
              kind,
              vendor: (finalFields.provider as string) || "Unknown Provider",
              amount_cents: parseAmount(
                finalFields.amountDue ||
                  finalFields.totalAmount ||
                  finalFields.patientResponsibility,
              ),
              due_at: finalFields.dueDate
                ? new Date(finalFields.dueDate as string).toISOString()
                : null,
              status: "OPEN",
              reference_id:
                ((finalFields.accountNumber ||
                  finalFields.claimNumber) as string) || null,
              notes: `Scanned from document on ${new Date().toLocaleDateString()}`,
              source_document_id: scan.id,
            })
            .select("id")
            .single();

        if (financialError || !financialItem) {
          console.error("Failed to create financial item:", financialError);
          throw new Error("Failed to create financial item");
        }

        targetId = financialItem.id;
        break;
      }

      case "HANDOFF": {
        // Build summary from extracted fields
        let summary: string;

        if (scan.document_type === "LAB_RESULT") {
          summary = `Lab Result: ${finalFields.testName || "Unknown Test"}\n`;
          summary += `Result: ${finalFields.result || "See attached document"}\n`;
          if (finalFields.normalRange)
            summary += `Normal Range: ${finalFields.normalRange}\n`;
          if (finalFields.performedDate)
            summary += `Date: ${finalFields.performedDate}\n`;
          if (finalFields.orderedBy)
            summary += `Ordered by: ${finalFields.orderedBy}\n`;
          if (finalFields.abnormal) summary += `\n⚠️ Result is abnormal`;
        } else if (scan.document_type === "DISCHARGE") {
          summary = `Hospital Discharge Summary\n\n`;
          if (finalFields.facility)
            summary += `Facility: ${finalFields.facility}\n`;
          if (finalFields.dischargeDate)
            summary += `Discharge Date: ${finalFields.dischargeDate}\n`;
          if (finalFields.diagnosis)
            summary += `\nDiagnosis: ${finalFields.diagnosis}\n`;
          if (finalFields.followUpInstructions) {
            summary += `\nFollow-up Instructions:\n${finalFields.followUpInstructions}\n`;
          }
          if (
            finalFields.medications &&
            Array.isArray(finalFields.medications)
          ) {
            summary += `\nMedications:\n${(finalFields.medications as string[]).map((m) => `• ${m}`).join("\n")}`;
          }
        } else {
          summary =
            scan.ocr_text?.slice(0, 1000) ||
            "Scanned document - see attachment";
        }

        // Create handoff draft
        const { data: handoff, error: handoffError } = await supabaseService
          .from("handoffs")
          .insert({
            circle_id: scan.circle_id,
            patient_id: scan.patient_id,
            created_by: user.id,
            handoff_type:
              scan.document_type === "DISCHARGE"
                ? "FACILITY_UPDATE"
                : "APPOINTMENT",
            status: "DRAFT",
            summary_json: {
              summary,
              keyDetails: Object.entries(finalFields)
                .filter(([_, v]) => v != null)
                .map(([k, v]) => `${k}: ${v}`)
                .slice(0, 5),
            },
            source_document_id: scan.id,
          })
          .select("id")
          .single();

        if (handoffError || !handoff) {
          console.error("Failed to create handoff:", handoffError);
          throw new Error("Failed to create handoff");
        }

        targetId = handoff.id;
        break;
      }

      case "INBOX": {
        // Create inbox item
        const { data: inboxItem, error: inboxError } = await supabaseService
          .from("inbox_items")
          .insert({
            circle_id: scan.circle_id,
            patient_id: scan.patient_id,
            created_by: user.id,
            item_type: "DOCUMENT",
            title: `Scanned Document - ${new Date().toLocaleDateString()}`,
            content: scan.ocr_text?.slice(0, 2000) || "See attached document",
            status: "PENDING",
            priority: "LOW",
            source_document_id: scan.id,
          })
          .select("id")
          .single();

        if (inboxError || !inboxItem) {
          console.error("Failed to create inbox item:", inboxError);
          throw new Error("Failed to create inbox item");
        }

        targetId = inboxItem.id;
        break;
      }

      default:
        throw new Error(`Unknown target type: ${targetType}`);
    }

    // Create attachment records for scan images
    const storageKeys = scan.storage_keys || [];
    const attachmentErrors: string[] = [];
    for (let i = 0; i < storageKeys.length; i++) {
      const { data: attachment, error: attachmentError } = await supabaseService
        .from("attachments")
        .insert({
          circle_id: scan.circle_id,
          uploader_user_id: user.id,
          kind: "PHOTO",
          mime_type: "image/jpeg",
          byte_size: 0, // Unknown at this point
          sha256: storageKeys[i], // Use storage key as pseudo-hash
          storage_key: storageKeys[i],
          filename: `scan_page_${i + 1}.jpg`,
          document_scan_id: scan.id,
          // Link to target entity based on type
          ...(targetType === "BINDER" ? { binder_item_id: targetId } : {}),
          ...(targetType === "HANDOFF" ? { handoff_id: targetId } : {}),
        })
        .select("id")
        .single();

      if (attachmentError) {
        attachmentErrors.push(`Page ${i + 1}: ${attachmentError.message}`);
        console.error("Failed to create attachment:", { scanId, page: i + 1 });
      } else if (attachment) {
        attachmentIds.push(attachment.id);
      }
    }

    // Warn if some attachments failed but continue if at least one succeeded
    if (
      attachmentErrors.length > 0 &&
      attachmentIds.length === 0 &&
      storageKeys.length > 0
    ) {
      // All attachments failed - this is a problem but don't fail the entire routing
      console.error("All attachment creations failed:", {
        scanId,
        errors: attachmentErrors,
      });
    }

    // Update scan as routed
    const { error: routeError } = await supabaseService
      .from("document_scans")
      .update({
        routed_to_type: targetType,
        routed_to_id: targetId,
        routed_at: new Date().toISOString(),
        routed_by: user.id,
        status: "ROUTED",
        updated_at: new Date().toISOString(),
      })
      .eq("id", scanId);

    if (routeError) {
      console.error("Failed to update scan as routed:", { scanId });
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "DATABASE_ERROR",
            message: "Failed to complete routing",
          },
        } as RouteResponse),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Create audit event (non-blocking - log error but don't fail)
    const { error: auditError } = await supabaseService
      .from("audit_events")
      .insert({
        circle_id: scan.circle_id,
        actor_user_id: user.id,
        event_type: "DOCUMENT_ROUTED",
        object_type: "document_scan",
        object_id: scanId,
        metadata_json: {
          document_type: scan.document_type,
          target_type: targetType,
          target_id: targetId,
          attachments_created: attachmentIds.length,
        },
      });

    if (auditError) {
      console.error("Failed to create audit event:", { scanId });
    }

    const response: RouteResponse = {
      success: true,
      targetId,
      targetType,
      attachmentIds,
    };

    return new Response(JSON.stringify(response), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error(
      "Error routing document:",
      error instanceof Error ? error.name : "Unknown error",
    );
    return new Response(
      JSON.stringify({
        success: false,
        error: {
          code: "INTERNAL_ERROR",
          message: "Internal server error",
        },
      } as RouteResponse),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
