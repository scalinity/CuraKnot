import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import {
  createClient,
  SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2.49.1";

interface ExpenseRecord {
  amount: number;
  category: string;
  expense_date: string;
}

const ALLOWED_ORIGINS = [
  "http://localhost:54321",
  "https://hiafuyxxwodhrmulpitk.supabase.co",
];

function getCorsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get("Origin") || "";
  const allowedOrigin = ALLOWED_ORIGINS.includes(origin)
    ? origin
    : ALLOWED_ORIGINS[0];
  return {
    "Access-Control-Allow-Origin": allowedOrigin,
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type",
    Vary: "Origin",
  };
}

interface EstimateCostsRequest {
  circle_id: string;
  patient_id: string;
  zip_code: string;
  scenarios: {
    type:
      | "CURRENT"
      | "FULL_TIME_HOME"
      | "TWENTY_FOUR_SEVEN"
      | "ASSISTED_LIVING"
      | "MEMORY_CARE"
      | "NURSING_HOME";
    home_care_hours?: number;
  }[];
}

interface CostBreakdown {
  category: string;
  amount: number;
}

interface ScenarioResult {
  type: string;
  scenario_name: string;
  monthly_total: number;
  yearly_total: number;
  breakdown: CostBreakdown[];
  compared_to_current: number;
}

interface EstimateCostsResponse {
  success: boolean;
  scenarios?: ScenarioResult[];
  local_cost_data?: {
    source: string;
    year: number;
    area_name: string;
  };
  error?: {
    code: string;
    message: string;
  };
}

interface LocalCostData {
  state: string;
  metro_area: string | null;
  zip_code_prefix: string | null;
  homemaker_services_hourly: number;
  home_health_aide_hourly: number;
  adult_day_health_daily: number;
  assisted_living_monthly: number;
  nursing_home_semi_private_daily: number;
  nursing_home_private_daily: number;
  memory_care_monthly: number | null;
  data_year: number;
}

const SCENARIO_NAMES: Record<string, string> = {
  CURRENT: "Current Care Setup",
  FULL_TIME_HOME: "Full-Time Home Care (40 hrs/week)",
  TWENTY_FOUR_SEVEN: "24/7 Home Care",
  ASSISTED_LIVING: "Assisted Living Facility",
  MEMORY_CARE: "Memory Care Facility",
  NURSING_HOME: "Nursing Home (Semi-Private)",
};

const VALID_SCENARIO_TYPES = new Set([
  "CURRENT",
  "FULL_TIME_HOME",
  "TWENTY_FOUR_SEVEN",
  "ASSISTED_LIVING",
  "MEMORY_CARE",
  "NURSING_HOME",
]);

// Minimum role required: CONTRIBUTOR (VIEWERs cannot access projections)
const PROJECTION_ALLOWED_ROLES = new Set(["CONTRIBUTOR", "ADMIN", "OWNER"]);

const WEEKS_PER_MONTH = 4.348;
const DAYS_PER_MONTH = 30.44;
const DEFAULT_MED_COST_PER_MONTH = 50;
const DEFAULT_SUPPLIES_MONTHLY = 150;
const DEFAULT_TRANSPORT_MONTHLY = 200;
const DEFAULT_PERSONAL_EXPENSES_MONTHLY = 300;

serve(async (req) => {
  const corsHeaders = getCorsHeaders(req);

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "AUTH_INVALID_TOKEN",
            message: "No authorization header",
          },
        } as EstimateCostsResponse),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");

    if (!supabaseUrl || !supabaseServiceKey || !supabaseAnonKey) {
      console.error("Missing required environment variables");
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "CONFIGURATION_ERROR",
            message: "Server configuration error",
          },
        } as EstimateCostsResponse),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const supabaseUser = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const supabaseService = createClient(supabaseUrl, supabaseServiceKey);

    const {
      data: { user },
      error: userError,
    } = await supabaseUser.auth.getUser();
    if (userError || !user) {
      return new Response(
        JSON.stringify({
          success: false,
          error: { code: "AUTH_INVALID_TOKEN", message: "Invalid token" },
        } as EstimateCostsResponse),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Validate Content-Type
    const contentType = req.headers.get("Content-Type") || "";
    if (!contentType.includes("application/json")) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "INVALID_CONTENT_TYPE",
            message: "Content-Type must be application/json",
          },
        } as EstimateCostsResponse),
        {
          status: 415,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const body: EstimateCostsRequest = await req.json();
    const { circle_id, patient_id, zip_code, scenarios } = body;

    // Validate required fields
    if (!circle_id || !patient_id) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "MISSING_FIELDS",
            message: "circle_id and patient_id are required",
          },
        } as EstimateCostsResponse),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Validate zip code format
    if (!zip_code || !/^\d{5}$/.test(zip_code)) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "INVALID_ZIP_CODE",
            message: "Zip code must be exactly 5 digits",
          },
        } as EstimateCostsResponse),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Validate scenarios
    if (!scenarios || scenarios.length === 0) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "INVALID_SCENARIOS",
            message: "At least one scenario is required",
          },
        } as EstimateCostsResponse),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    if (scenarios.length > 10) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "INVALID_SCENARIOS",
            message: "Maximum 10 scenarios per request",
          },
        } as EstimateCostsResponse),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    for (const scenario of scenarios) {
      if (!VALID_SCENARIO_TYPES.has(scenario.type)) {
        return new Response(
          JSON.stringify({
            success: false,
            error: {
              code: "INVALID_SCENARIO_TYPE",
              message: `Invalid scenario type: ${scenario.type}`,
            },
          } as EstimateCostsResponse),
          {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }
    }

    // Validate home_care_hours bounds (0-168 hours per week)
    for (const scenario of scenarios) {
      if (
        scenario.home_care_hours !== undefined &&
        scenario.home_care_hours !== null
      ) {
        const hours = Number(scenario.home_care_hours);
        if (isNaN(hours) || hours < 0 || hours > 168) {
          return new Response(
            JSON.stringify({
              success: false,
              error: {
                code: "INVALID_HOME_CARE_HOURS",
                message:
                  "Home care hours must be between 0 and 168 (hours per week)",
              },
            } as EstimateCostsResponse),
            {
              status: 400,
              headers: {
                ...corsHeaders,
                "Content-Type": "application/json",
              },
            },
          );
        }
      }
    }

    // Verify circle membership and role
    const { data: membership } = await supabaseService
      .from("circle_members")
      .select("role")
      .eq("circle_id", circle_id)
      .eq("user_id", user.id)
      .eq("status", "ACTIVE")
      .single();

    if (!membership) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "AUTH_NOT_MEMBER",
            message: "Not a member of this circle",
          },
        } as EstimateCostsResponse),
        {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Check role: VIEWER cannot access projections
    if (!PROJECTION_ALLOWED_ROLES.has(membership.role)) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "AUTH_INSUFFICIENT_ROLE",
            message: "Insufficient permissions to access cost projections",
          },
        } as EstimateCostsResponse),
        {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Check subscription tier - projections require FAMILY plan
    const { data: subscription } = await supabaseService
      .from("subscriptions")
      .select("plan_id, status")
      .eq("user_id", user.id)
      .in("status", ["ACTIVE", "TRIALING"])
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    const userPlan = subscription?.plan_id || "FREE";

    if (userPlan !== "FAMILY") {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "SUBSCRIPTION_REQUIRED",
            message:
              "Cost projections require the Family plan. Please upgrade to access this feature.",
          },
        } as EstimateCostsResponse),
        {
          status: 402,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Verify patient exists in circle
    const { data: patient } = await supabaseService
      .from("patients")
      .select("id, display_name")
      .eq("id", patient_id)
      .eq("circle_id", circle_id)
      .single();

    if (!patient) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "PATIENT_NOT_FOUND",
            message: "Patient not found in this circle",
          },
        } as EstimateCostsResponse),
        {
          status: 404,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Look up local care costs with fallback chain
    const zipPrefix = zip_code.substring(0, 3);
    const costData = await lookupLocalCosts(supabaseService, zipPrefix);

    if (!costData) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "COST_DATA_UNAVAILABLE",
            message:
              "Unable to find care cost data for this area. Please try a different zip code.",
          },
        } as EstimateCostsResponse),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Count active medications for estimate
    const { data: meds } = await supabaseService
      .from("binder_items")
      .select("id")
      .eq("circle_id", circle_id)
      .eq("patient_id", patient_id)
      .eq("type", "MED")
      .eq("is_active", true);

    const activeMedCount = meds?.length || 0;
    const medicationsEstimate =
      activeMedCount > 0
        ? activeMedCount * DEFAULT_MED_COST_PER_MONTH
        : 3 * DEFAULT_MED_COST_PER_MONTH; // Default assumption: 3 meds

    // Get current expenses (last 3 months average) for CURRENT scenario
    const threeMonthsAgo = new Date();
    threeMonthsAgo.setMonth(threeMonthsAgo.getMonth() - 3);

    const { data: recentExpenses } = await supabaseService
      .from("care_expenses")
      .select("amount, category, expense_date")
      .eq("circle_id", circle_id)
      .eq("patient_id", patient_id)
      .gte("expense_date", threeMonthsAgo.toISOString().split("T")[0]);

    // Calculate scenario results
    const results: ScenarioResult[] = [];
    let currentMonthly = 0;

    // Calculate current monthly first (needed for compared_to_current)
    if (recentExpenses && recentExpenses.length > 0) {
      const totalExpenses = recentExpenses.reduce(
        (
          sum: number,
          e: { amount: number; category: string; expense_date: string },
        ) => sum + (Number(e.amount) || 0),
        0,
      );
      // Calculate months spanned using calendar months
      const dates = recentExpenses.map(
        (e: { amount: number; category: string; expense_date: string }) =>
          new Date(e.expense_date),
      );
      const minDate = new Date(
        Math.min(...dates.map((d: Date) => d.getTime())),
      );
      const maxDate = new Date(
        Math.max(...dates.map((d: Date) => d.getTime())),
      );
      const monthsSpanned = Math.max(
        1,
        (maxDate.getFullYear() - minDate.getFullYear()) * 12 +
          (maxDate.getMonth() - minDate.getMonth()) +
          1,
      );
      currentMonthly = totalExpenses / monthsSpanned;
    }

    for (const scenario of scenarios) {
      const result = calculateScenario(
        scenario.type,
        costData,
        medicationsEstimate,
        currentMonthly,
        recentExpenses || [],
        scenario.home_care_hours,
      );
      results.push(result);
    }

    // If we calculated a CURRENT scenario, update currentMonthly from its result
    const currentScenario = results.find((r) => r.type === "CURRENT");
    if (currentScenario) {
      currentMonthly = currentScenario.monthly_total;
    }

    // Update compared_to_current for non-CURRENT scenarios
    for (const result of results) {
      if (result.type !== "CURRENT" && currentMonthly > 0) {
        result.compared_to_current = Math.round(
          result.monthly_total - currentMonthly,
        );
      }
    }

    // Upsert estimates to care_cost_estimates table
    const upsertRows = results.map((result) => {
      // Parse breakdown into individual monthly fields
      const breakdownMap: Record<string, number> = {};
      for (const item of result.breakdown) {
        const cat = item.category.toLowerCase();
        if (cat.includes("home") || cat.includes("aide")) {
          breakdownMap["home_care_monthly"] =
            (breakdownMap["home_care_monthly"] || 0) + item.amount;
        } else if (cat.includes("medication")) {
          breakdownMap["medications_monthly"] = item.amount;
        } else if (cat.includes("suppli")) {
          breakdownMap["supplies_monthly"] = item.amount;
        } else if (cat.includes("transport")) {
          breakdownMap["transportation_monthly"] = item.amount;
        } else if (
          cat.includes("facility") ||
          cat.includes("living") ||
          cat.includes("nursing") ||
          cat.includes("memory")
        ) {
          breakdownMap["facility_monthly"] =
            (breakdownMap["facility_monthly"] || 0) + item.amount;
        } else {
          breakdownMap["other_monthly"] =
            (breakdownMap["other_monthly"] || 0) + item.amount;
        }
      }

      return {
        circle_id,
        patient_id,
        scenario_name: result.scenario_name,
        scenario_type: result.type,
        is_current: result.type === "CURRENT",
        home_care_monthly: breakdownMap["home_care_monthly"] || null,
        medications_monthly: breakdownMap["medications_monthly"] || null,
        supplies_monthly: breakdownMap["supplies_monthly"] || null,
        transportation_monthly: breakdownMap["transportation_monthly"] || null,
        facility_monthly: breakdownMap["facility_monthly"] || null,
        other_monthly: breakdownMap["other_monthly"] || null,
        total_monthly: result.monthly_total,
        out_of_pocket_monthly: result.monthly_total,
        data_source: costData.metro_area || costData.state,
        data_year: costData.data_year,
        updated_at: new Date().toISOString(),
      };
    });

    // Batch upsert all scenarios at once
    const { error: upsertError } = await supabaseService
      .from("care_cost_estimates")
      .upsert(upsertRows, {
        onConflict: "circle_id,patient_id,scenario_type",
      });

    if (upsertError) {
      console.error("Failed to upsert estimates:", upsertError.message);
    }

    // Log audit event
    await supabaseService.from("audit_events").insert({
      circle_id,
      actor_user_id: user.id,
      event_type: "COST_ESTIMATE_GENERATED",
      object_type: "care_cost_estimate",
      object_id: patient_id,
      metadata_json: {
        patient_id,
        zip_code,
        scenarios: scenarios.map((s) => s.type),
        cost_data_source: costData.metro_area || costData.state,
      },
    });

    const areaName = costData.metro_area
      ? `${costData.metro_area}, ${costData.state}`
      : costData.state === "US"
        ? "National Average"
        : `${costData.state} State Average`;

    const response: EstimateCostsResponse = {
      success: true,
      scenarios: results,
      local_cost_data: {
        source: costData.metro_area
          ? "metro"
          : costData.zip_code_prefix
            ? "zip_prefix"
            : costData.state === "US"
              ? "national"
              : "state",
        year: costData.data_year,
        area_name: areaName,
      },
    };

    return new Response(JSON.stringify(response), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    const corsHeaders = getCorsHeaders(req);
    console.error("Estimate care costs error:", (error as Error).message);
    return new Response(
      JSON.stringify({
        success: false,
        error: {
          code: "CALCULATION_ERROR",
          message: "Failed to estimate care costs",
        },
      } as EstimateCostsResponse),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});

async function lookupLocalCosts(
  supabase: SupabaseClient,
  zipPrefix: string,
): Promise<LocalCostData | null> {
  // Step 1: Try zip_code_prefix match
  const { data: zipMatch } = await supabase
    .from("local_care_costs")
    .select("*")
    .eq("zip_code_prefix", zipPrefix)
    .limit(1)
    .maybeSingle();

  if (zipMatch) return zipMatch;

  // Step 2: Look up state from zip prefix and try state-level
  const { data: stateFromZip } = await supabase
    .from("local_care_costs")
    .select("state")
    .like("zip_code_prefix", `${zipPrefix.substring(0, 2)}%`)
    .limit(1)
    .maybeSingle();

  if (stateFromZip) {
    const { data: stateMatch } = await supabase
      .from("local_care_costs")
      .select("*")
      .eq("state", stateFromZip.state)
      .is("zip_code_prefix", null)
      .is("metro_area", null)
      .limit(1)
      .maybeSingle();

    if (stateMatch) return stateMatch;
  }

  // Step 3: National fallback
  const { data: nationalMatch } = await supabase
    .from("local_care_costs")
    .select("*")
    .eq("state", "US")
    .is("metro_area", null)
    .is("zip_code_prefix", null)
    .limit(1)
    .maybeSingle();

  return nationalMatch;
}

function calculateScenario(
  type: string,
  costData: LocalCostData,
  medicationsEstimate: number,
  currentMonthly: number,
  recentExpenses: ExpenseRecord[],
  homeCareHours?: number,
): ScenarioResult {
  const breakdown: CostBreakdown[] = [];
  let monthlyTotal = 0;

  switch (type) {
    case "CURRENT": {
      if (recentExpenses.length > 0) {
        // Group by category and average over months
        const categoryTotals: Record<string, number> = {};
        for (const expense of recentExpenses) {
          const cat = expense.category || "Other";
          categoryTotals[cat] =
            (categoryTotals[cat] || 0) + (Number(expense.amount) || 0);
        }

        // Calculate months spanned using calendar months
        const dates = recentExpenses.map(
          (e: ExpenseRecord) => new Date(e.expense_date),
        );
        const minDate = new Date(
          Math.min(...dates.map((d: Date) => d.getTime())),
        );
        const maxDate = new Date(
          Math.max(...dates.map((d: Date) => d.getTime())),
        );
        const monthsSpanned = Math.max(
          1,
          (maxDate.getFullYear() - minDate.getFullYear()) * 12 +
            (maxDate.getMonth() - minDate.getMonth()) +
            1,
        );

        for (const [category, total] of Object.entries(categoryTotals)) {
          const monthlyAmount = Math.round(total / monthsSpanned);
          breakdown.push({ category, amount: monthlyAmount });
          monthlyTotal += monthlyAmount;
        }
      } else {
        // No expense data - estimate from home_care_hours or default
        const hours = homeCareHours || 20;
        const homeCare = Math.round(
          hours * WEEKS_PER_MONTH * costData.home_health_aide_hourly,
        );
        breakdown.push({ category: "Home Care", amount: homeCare });
        breakdown.push({
          category: "Medications",
          amount: medicationsEstimate,
        });
        breakdown.push({
          category: "Supplies",
          amount: DEFAULT_SUPPLIES_MONTHLY,
        });
        breakdown.push({
          category: "Transportation",
          amount: DEFAULT_TRANSPORT_MONTHLY,
        });
        monthlyTotal =
          homeCare +
          medicationsEstimate +
          DEFAULT_SUPPLIES_MONTHLY +
          DEFAULT_TRANSPORT_MONTHLY;
      }
      break;
    }

    case "FULL_TIME_HOME": {
      const homeCare = Math.round(
        40 * WEEKS_PER_MONTH * costData.home_health_aide_hourly,
      );
      breakdown.push({
        category: "Home Health Aide (40 hrs/wk)",
        amount: homeCare,
      });
      breakdown.push({ category: "Medications", amount: medicationsEstimate });
      breakdown.push({
        category: "Supplies",
        amount: DEFAULT_SUPPLIES_MONTHLY,
      });
      breakdown.push({
        category: "Transportation",
        amount: DEFAULT_TRANSPORT_MONTHLY,
      });
      monthlyTotal =
        homeCare +
        medicationsEstimate +
        DEFAULT_SUPPLIES_MONTHLY +
        DEFAULT_TRANSPORT_MONTHLY;
      break;
    }

    case "TWENTY_FOUR_SEVEN": {
      // Blended rate: 70% homemaker + 30% home health aide for 168 hrs/week
      const blendedHourly =
        costData.homemaker_services_hourly * 0.7 +
        costData.home_health_aide_hourly * 0.3;
      const homeCare = Math.round(168 * WEEKS_PER_MONTH * blendedHourly);
      breakdown.push({
        category: "24/7 Home Care (blended rate)",
        amount: homeCare,
      });
      breakdown.push({ category: "Medications", amount: medicationsEstimate });
      breakdown.push({
        category: "Supplies",
        amount: DEFAULT_SUPPLIES_MONTHLY,
      });
      breakdown.push({
        category: "Transportation",
        amount: DEFAULT_TRANSPORT_MONTHLY,
      });
      monthlyTotal =
        homeCare +
        medicationsEstimate +
        DEFAULT_SUPPLIES_MONTHLY +
        DEFAULT_TRANSPORT_MONTHLY;
      break;
    }

    case "ASSISTED_LIVING": {
      const facilityFee = costData.assisted_living_monthly;
      breakdown.push({
        category: "Assisted Living Facility",
        amount: facilityFee,
      });
      breakdown.push({ category: "Medications", amount: medicationsEstimate });
      breakdown.push({
        category: "Personal Expenses",
        amount: DEFAULT_PERSONAL_EXPENSES_MONTHLY,
      });
      monthlyTotal =
        facilityFee + medicationsEstimate + DEFAULT_PERSONAL_EXPENSES_MONTHLY;
      break;
    }

    case "MEMORY_CARE": {
      const memoryCare =
        costData.memory_care_monthly ||
        Math.round(costData.assisted_living_monthly * 1.5);
      breakdown.push({ category: "Memory Care Facility", amount: memoryCare });
      breakdown.push({ category: "Medications", amount: medicationsEstimate });
      monthlyTotal = memoryCare + medicationsEstimate;
      break;
    }

    case "NURSING_HOME": {
      const nursingHome = Math.round(
        costData.nursing_home_semi_private_daily * DAYS_PER_MONTH,
      );
      breakdown.push({
        category: "Nursing Home (Semi-Private)",
        amount: nursingHome,
      });
      breakdown.push({ category: "Medications", amount: medicationsEstimate });
      monthlyTotal = nursingHome + medicationsEstimate;
      break;
    }
  }

  return {
    type,
    scenario_name: SCENARIO_NAMES[type] || type,
    monthly_total: Math.round(monthlyTotal),
    yearly_total: Math.round(monthlyTotal * 12),
    breakdown,
    compared_to_current: 0, // Will be updated after all scenarios are calculated
  };
}
