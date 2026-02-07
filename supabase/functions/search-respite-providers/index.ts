import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface SearchRequest {
  latitude: number;
  longitude: number;
  radiusMiles: number;
  providerType?: string;
  services?: string[];
  minRating?: number;
  maxPrice?: number;
  verifiedOnly?: boolean;
  limit?: number;
  offset?: number;
}

interface ProviderRow {
  id: string;
  name: string;
  provider_type: string;
  description: string | null;
  address: string | null;
  city: string | null;
  state: string | null;
  zip_code: string | null;
  latitude: string;
  longitude: string;
  phone: string | null;
  email: string | null;
  website: string | null;
  hours_json: Record<string, unknown> | null;
  pricing_model: string | null;
  price_min: string | null;
  price_max: string | null;
  accepts_medicaid: boolean;
  accepts_medicare: boolean;
  scholarships_available: boolean;
  services_json: string[];
  verification_status: string;
  avg_rating: string;
  review_count: number;
  distance_miles: string;
}

function isValidHttpUrl(urlString: string): boolean {
  try {
    const url = new URL(urlString);
    return url.protocol === "http:" || url.protocol === "https:";
  } catch {
    return false;
  }
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")!;

    // Validate JWT
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "AUTH_INVALID_TOKEN",
            message: "Missing authorization",
          },
        }),
        {
          status: 401,
          headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
        },
      );
    }

    const supabaseUser = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const {
      data: { user },
      error: authError,
    } = await supabaseUser.auth.getUser();
    if (authError || !user) {
      return new Response(
        JSON.stringify({
          success: false,
          error: { code: "AUTH_INVALID_TOKEN", message: "Invalid token" },
        }),
        {
          status: 401,
          headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
        },
      );
    }

    // Rate limit check (60 requests per minute per user)
    const supabaseService = createClient(supabaseUrl, supabaseServiceKey);
    const { data: withinLimit } = await supabaseService.rpc(
      "check_rate_limit",
      {
        p_user_id: user.id,
        p_endpoint: "search-respite-providers",
        p_max_requests: 60,
        p_window_seconds: 60,
      },
    );

    if (withinLimit === false) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "RATE_LIMITED",
            message: "Too many requests. Please try again shortly.",
          },
        }),
        {
          status: 429,
          headers: {
            ...CORS_HEADERS,
            "Content-Type": "application/json",
            "Retry-After": "60",
          },
        },
      );
    }

    // Parse and validate request
    const body: SearchRequest | null = await req.json().catch(() => null);
    if (!body) {
      return new Response(
        JSON.stringify({
          success: false,
          error: { code: "VALIDATION_ERROR", message: "Invalid JSON body" },
        }),
        {
          status: 400,
          headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
        },
      );
    }

    if (
      typeof body.latitude !== "number" ||
      typeof body.longitude !== "number" ||
      body.latitude < -90 ||
      body.latitude > 90 ||
      body.longitude < -180 ||
      body.longitude > 180
    ) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "VALIDATION_ERROR",
            message: "Invalid latitude or longitude",
          },
        }),
        {
          status: 400,
          headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
        },
      );
    }

    const radiusMiles = body.radiusMiles ?? 25;
    if (
      typeof radiusMiles !== "number" ||
      radiusMiles <= 0 ||
      radiusMiles > 500
    ) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "VALIDATION_ERROR",
            message: "Radius must be between 1 and 500 miles",
          },
        }),
        {
          status: 400,
          headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
        },
      );
    }

    const limit = Math.min(Math.max(body.limit ?? 20, 1), 100);
    const offset = Math.max(body.offset ?? 0, 0);

    // Validate providerType enum (if provided)
    const VALID_PROVIDER_TYPES = [
      "ADULT_DAY",
      "IN_HOME",
      "OVERNIGHT",
      "VOLUNTEER",
      "EMERGENCY",
    ];
    if (
      body.providerType &&
      !VALID_PROVIDER_TYPES.includes(body.providerType)
    ) {
      return new Response(
        JSON.stringify({
          success: false,
          error: {
            code: "VALIDATION_ERROR",
            message: "Invalid provider type",
          },
        }),
        {
          status: 400,
          headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
        },
      );
    }

    // Validate optional filter bounds
    const minRating =
      body.minRating && body.minRating > 0 && body.minRating <= 5
        ? body.minRating
        : null;
    const maxPrice =
      body.maxPrice && body.maxPrice > 0 && body.maxPrice <= 100000
        ? body.maxPrice
        : null;

    // Validate services filter elements (each must be non-empty string, max 100 chars, max 20 items)
    let servicesParam: string[] | null = null;
    if (
      body.services &&
      Array.isArray(body.services) &&
      body.services.length > 0
    ) {
      if (body.services.length > 20) {
        return new Response(
          JSON.stringify({
            success: false,
            error: {
              code: "VALIDATION_ERROR",
              message: "Too many service filters (max 20)",
            },
          }),
          {
            status: 400,
            headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
          },
        );
      }
      const validServices = body.services.filter(
        (s): s is string =>
          typeof s === "string" && s.trim().length > 0 && s.length <= 100,
      );
      servicesParam = validServices.length > 0 ? validServices : null;
    }

    // Check subscription tier to gate contact info (default to false on error)
    const { data: hasContactAccess, error: featureError } =
      await supabaseService.rpc("has_feature_access", {
        p_user_id: user.id,
        p_feature: "respite_requests",
      });

    if (featureError) {
      console.error(
        "Feature check failed for user:",
        user.id,
        "error:",
        featureError.code ?? "UNKNOWN",
        featureError.message ?? "",
      );
    }

    // Safe default: hide contact info if feature check fails
    const canSeeContacts = featureError ? false : !!hasContactAccess;

    // Execute Haversine geo search with all filters in SQL
    // Pass services as array — Supabase SDK auto-serializes to JSONB for RPC
    const { data: providers, error: queryError } = await supabaseService.rpc(
      "search_providers_by_radius",
      {
        p_latitude: body.latitude,
        p_longitude: body.longitude,
        p_radius_miles: radiusMiles,
        p_limit: limit + 1, // Fetch one extra to check hasMore
        p_offset: offset,
        p_provider_type: body.providerType ?? null,
        p_min_rating: minRating,
        p_max_price: maxPrice,
        p_verified_only: body.verifiedOnly ?? false,
        p_services: servicesParam,
      },
    );

    if (queryError) {
      console.error(
        "Provider search query failed:",
        queryError.code ?? "UNKNOWN",
        queryError.message ?? "",
      );
      return new Response(
        JSON.stringify({
          success: false,
          error: { code: "DATABASE_ERROR", message: "Search failed" },
        }),
        {
          status: 500,
          headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
        },
      );
    }

    const allResults: ProviderRow[] = providers ?? [];

    // Determine hasMore accurately (filters applied in SQL, so count is correct)
    const hasMore = allResults.length > limit;
    const results = allResults.slice(0, limit);

    // Transform to camelCase response, stripping contact info for FREE tier
    const response = results.map((p: ProviderRow) => {
      const avgRating = parseFloat(p.avg_rating);
      const distanceMiles = parseFloat(p.distance_miles);
      const lat = parseFloat(p.latitude);
      const lng = parseFloat(p.longitude);
      const priceMin = p.price_min ? parseFloat(p.price_min) : null;
      const priceMax = p.price_max ? parseFloat(p.price_max) : null;

      return {
        id: p.id,
        name: p.name,
        providerType: p.provider_type,
        description: p.description,
        address: p.address,
        city: p.city,
        state: p.state,
        zipCode: p.zip_code,
        latitude: isNaN(lat) ? 0 : lat,
        longitude: isNaN(lng) ? 0 : lng,
        phone: canSeeContacts ? p.phone : null,
        email: canSeeContacts ? p.email : null,
        website:
          canSeeContacts && p.website && isValidHttpUrl(p.website)
            ? p.website
            : null,
        hoursJson: p.hours_json,
        pricingModel: p.pricing_model,
        priceMin: priceMin !== null && !isNaN(priceMin) ? priceMin : null,
        priceMax: priceMax !== null && !isNaN(priceMax) ? priceMax : null,
        acceptsMedicaid: p.accepts_medicaid,
        acceptsMedicare: p.accepts_medicare,
        scholarshipsAvailable: p.scholarships_available,
        services: p.services_json ?? [],
        verificationStatus: p.verification_status,
        avgRating: isNaN(avgRating) ? 0 : avgRating,
        reviewCount: p.review_count,
        distanceMiles: isNaN(distanceMiles) ? null : distanceMiles,
      };
    });

    return new Response(
      JSON.stringify({
        success: true,
        providers: response,
        total: response.length,
        hasMore,
      }),
      {
        status: 200,
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error("Unexpected error in search-respite-providers");
    return new Response(
      JSON.stringify({
        success: false,
        error: { code: "INTERNAL_ERROR", message: "Internal server error" },
      }),
      {
        status: 500,
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      },
    );
  }
});
