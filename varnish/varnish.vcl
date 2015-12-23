# Varnish reverse-proxy configuration (managed by Puppet)
#

vcl 4.0;

# libraries
import std;
import directors;

# backends
include "/etc/varnish/backends.vcl";

sub vcl_recv {

  if (req.http.X-Forwarded-For && req.http.X-Forwarded-For != "unknown") {
    std.collect(req.http.X-Forwarded-For); # ensure we get only ONE header
      set req.http.X-Forwarded-For = regsub(req.http.X-Forwarded-For, ", 10\.220+\.[0-9]+\.[0-9]+", ""); # remove the ELB ip address
      set req.http.X-Forwarded-For = regsub(req.http.x-forwarded-for, "^(|.* )([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)(|, unknown)$", "\2"); # get last IP from the field
  } else {
    set req.http.X-Forwarded-For = client.ip;
  }
# Use Origin header if Referer is not present
  if (! req.http.referer && req.http.origin) {
    set req.http.Referer = req.http.Origin;
  }

## misc blacklisted patterns
#  include "/etc/varnish/blacklist.vcl";

# Varnish "checker" URL for ELB probes
  if (req.url ~ "^/elbHealthcheckF5BG") {
    return (synth(200, "Varnish working fine"));
    set req.http.Connection = "close";
  }

# Remove all Google Analytics cookies
  set req.http.cookie = regsuball(req.http.cookie, "(^|;\s*)(_[_a-z]+)=[^;]*", "");
# Remove ; prefix if present
  set req.http.cookie = regsub(req.http.cookie, "^;\s*", "");
# Remove cookie if empty
  if (req.http.cookie == "") {
    unset req.http.cookie;
  }
## production URLs redirections
#  include "/etc/varnish/redirects-recv.production.vcl";
#
## production URLs
#  include "/etc/varnish/routing.production.vcl";
#  include "/etc/varnish/routing.schweizmobil.vcl";
#
## integration URLs
#  include "/etc/varnish/routing.integration.vcl";
#
## development URLs
#  include "/etc/varnish/routing.development.vcl";
#
## demo URLs
#  include "/etc/varnish/routing.demo.vcl";
#
## ci URLs
#  include "/etc/varnish/routing.ci.vcl";

  else {
    return(synth(404, "Unknown virtual host"));
  }

  /* enforce client Cache-Control policy */
  if (req.http.Cache-Control ~ "private|no-cache|no-store") {
    std.log("NO_CACHE:Client_No_Cache");
    return(pass);
  }

  /* enforce cache policy defined upstream in VCL */
  if (req.http.x-varnish-cache-policy == "bypass") {
    unset req.http.x-varnish-cache-policy;
    std.log("NO_CACHE:Policy_No_Cache");
    return(pass);
  }

# < begin of the default subroutine >
# Override the default VCL logic of the vcl_recv and add a "return (lookup)"
# at the end to avoid appending the built-in default code of this subroutine
  if (req.method != "GET" &&
      req.method != "HEAD" &&
      req.method != "PUT" &&
      req.method != "POST" &&
      req.method != "TRACE" &&
      req.method != "OPTIONS" &&
      req.method != "DELETE") {
    /* Non-RFC2616 or CONNECT which is weird. */
    return (pipe);
  }

  if (req.method != "GET" && req.method != "HEAD") {
    /* We only deal with GET and HEAD by default */
    std.log("NO_CACHE:Method_" + req.method);
    return (pass);
  }

  if ((req.http.Authorization && req.http.Authorization !~ "AWS") || req.http.Cookie) {
    /* Not cacheable by default */
    std.log("NO_CACHE:Cookie_or_Auth");
    return (pass);
  }
# < end of the default subroutine >

# Avoid appending default subroutine code !!!
#return (lookup);

}

#
# S3 filtering
#
sub vcl_backend_response {

  set beresp.http.X-Backend-Ip = beresp.backend.ip;
  set beresp.http.X-Backend-Retries = bereq.retries;

  # Deactivate streaming for all but downloaded files like
  # "print service" outputs
  if (beresp.http.Content-Disposition !~ "attachment") {
    set beresp.do_stream = false;
  }

  # Keep s3 content a bit longer
  if (beresp.backend.name ~ "^s3_") {
    set beresp.ttl = 30d;
  }

  if (
      bereq.backend == s3_wmts_tiles ||
      bereq.backend == s3_tms3d
     ) {
    set beresp.http.Expires = "Thu, 31 Dec 2037 23:55:55 GMT";
    set beresp.http.Cache-Control = "public, max-age=315360000";
    set beresp.http.Access-Control-Allow-Origin = "*";

    if (beresp.status >= 400) {
      set beresp.status = 204;
    }
  }


  if (bereq.backend == s3_wmts_schweizmobil) {
    set beresp.http.Access-Control-Allow-Origin = "*";
    set beresp.ttl = 30d;
  }

  if (
    bereq.backend == s3_wmts_schweizmobil &&
    !beresp.http.Cache-Control
    ) {
    set beresp.http.Cache-Control = "public";
  }

  if (
      bereq.backend == s3_chmobil3d
     ) {
    set beresp.http.Access-Control-Allow-Origin = "*";
    set beresp.http.Content-Encoding = "gzip";

    if (beresp.status >= 400) {
      set beresp.status = 204;
    }
  }

  /* see RT#189422 */
  if (
      bereq.http.host == "web-dashboard.dev.bgdi.ch" ||
      bereq.http.host == "web-dashboard.int.bgdi.ch" ||
      bereq.http.host == "web-dashboard.prod.bgdi.ch"
     ) {
    if (bereq.url ~ "events$") {
      set bereq.http.connection = "close";
    }
  }

  /* enforce backend Cache-Control policy */
  if (! beresp.http.Cache-Control || beresp.http.Cache-Control ~ "private|no-cache|no-store") {
    set beresp.uncacheable = true;
    std.log("NO_CACHE:Cache_Control");
    return(deliver);
  }

  /* ensure we do not cache any non-200 */
  if (beresp.status != 200) {
    std.log("NO_CACHE:No_200");
    set beresp.uncacheable = true;
    return(deliver);
  }
}

#
# Add a header indicating hit/miss
#
sub vcl_deliver {
  if (obj.hits > 0) {
    set resp.http.X-Cache = "HIT";
    set resp.http.X-Cache-Hits = obj.hits;
  } else {
    set resp.http.X-Cache = "MISS";
  }

  std.log("Backend:" + resp.http.X-Backend-Instance);
  std.log("backend_used:" + resp.http.X-Backend-Ip);
  std.log("retries:" + resp.http.X-Backend-Retries);

  unset resp.http.X-Backend-Instance;
  unset resp.http.X-Backend-Ip;
  unset resp.http.X-Backend-Retries;
  unset resp.http.X-No-Cache;

  unset resp.http.x-amz-meta-s3cmd-attrs;
  unset resp.http.x-amz-id-2;
  unset resp.http.x-amz-request-id;

  if (resp.status == 204) {
    return(synth(204));
  }
}

sub vcl_synth {
## production URLs redirections
#  include "/etc/varnish/redirects.production.vcl";

# Ensure we do not deliver any content on 204
  if (resp.status == 204) {
    set resp.http.Content-Type = "text/plain";
    set resp.http.Access-Control-Allow-Origin = "*";
    set resp.http.Connection = "close";
    synthetic("");
    return(deliver);
  }
}

sub vcl_backend_error {

  if (beresp.status >= 500 && beresp.status <= 504 && bereq.retries < 1) {
    return(retry);
  }
  set beresp.http.X-Backend-Ip = beresp.backend.ip;
  set beresp.http.X-Backend-Retries = bereq.retries;
}
