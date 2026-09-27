// Cloudflare Pages Function: POST /subscribe
// Adds an email to the Resend audience (launch + release notes list).
//
// Env vars (set in the Pages project dashboard, encrypted):
//   RESEND_API_KEY      Resend API key (Full access or Audiences-scoped)
//   RESEND_AUDIENCE_ID  ID of the audience to add contacts to
//
// Accepts a normal HTML form post (application/x-www-form-urlencoded) or
// JSON {"email": "..."}. Progressive enhancement: form posts without JS get
// a 303 redirect back to /?subscribed=1; fetch() callers get JSON.

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function wantsJson(request) {
    const accept = request.headers.get("accept") || "";
    return accept.includes("application/json");
}

function respond(request, url, ok, status) {
    if (wantsJson(request)) {
        return new Response(JSON.stringify({ ok }), {
            status,
            headers: { "content-type": "application/json" },
        });
    }
    const dest = new URL(ok ? "/?subscribed=1" : "/?subscribed=0", url);
    return Response.redirect(dest.toString(), 303);
}

export async function onRequestPost({ request, env }) {
    let email = "";
    let honeypot = "";
    const ctype = request.headers.get("content-type") || "";
    try {
        if (ctype.includes("application/json")) {
            const body = await request.json();
            email = (body.email || "").trim();
            honeypot = (body.website || "").trim();
        } else {
            const form = await request.formData();
            email = (form.get("email") || "").trim();
            honeypot = (form.get("website") || "").trim();
        }
    } catch {
        return respond(request, request.url, false, 400);
    }

    // Honeypot filled = bot. Pretend success, add nothing.
    if (honeypot) return respond(request, request.url, true, 200);

    if (!email || email.length > 254 || !EMAIL_RE.test(email)) {
        return respond(request, request.url, false, 400);
    }
    if (!env.RESEND_API_KEY || !env.RESEND_AUDIENCE_ID) {
        return respond(request, request.url, false, 500);
    }

    const res = await fetch(
        `https://api.resend.com/audiences/${env.RESEND_AUDIENCE_ID}/contacts`,
        {
            method: "POST",
            headers: {
                Authorization: `Bearer ${env.RESEND_API_KEY}`,
                "content-type": "application/json",
            },
            body: JSON.stringify({ email, unsubscribed: false }),
        },
    );

    // 2xx = created; 409 = already subscribed — both are success for the user.
    const ok = res.ok || res.status === 409;
    return respond(request, request.url, ok, ok ? 200 : 502);
}
