#' Function to make make multiple args of the same name from a 
#' single input with length > 1
#' @param x Value
makemultiargs <- function(x){
  value <- get(x, envir = parent.frame(n = 2))
  if ( length(value) == 0 ) { 
    NULL 
  } else {
    if ( any(sapply(value, is.na)) ) { 
      NULL 
    } else {
      if ( !is.character(value) ) { 
        value <- as.character(value)
      }
      names(value) <- rep(x, length(value))
      value
    }
  }
}

make_multiargs <- function(z, lst) {
  value <- lst[[z]]
  if (length(value) == 0) { 
    return(NULL)
  } else {
    if (any(sapply(value, is.na))) { 
      return(NULL)
    } else {
      if ( !is.character(value) ) { 
        value <- as.character(value)
      }
      names(value) <- rep(z, length(value))
      value
    }
  }
}

popp <- function(x, nms) {
  x[!names(x) %in% nms]
}

# Function to make a list of args passing arg names through multiargs function
collectargs <- function(x, lst){
  outlist <- list()
  for (i in seq_along(x)) {
    #outlist[[i]] <- makemultiargs(x[[i]])
    outlist[[i]] <- make_multiargs(x[[i]], lst)
  }
  as.list(unlist(sc(outlist)))
}

solr_GET <- function(base, path, args, callopts = NULL, ...) {
  cli <- crul::HttpClient$new(url = base, opts = callopts)
  res <- cli$get(path = path, query = args)
  if (res$status_code > 201) {
    solr_error(res)
  } else {
    res$parse("UTF-8")
  }
}

solr_error <- function(x) {
  if (grepl("html", x$response_headers$`content-type`)) {
    stat <- x$status_http()
    stop(sprintf('(%s) %s - %s', 
                 stat$status_code, stat$message, stat$explanation))
  } else { 
    err <- jsonlite::fromJSON(x$parse("UTF-8"))
    erropt <- Sys.getenv("SOLR_ERRORS")
    if (erropt == "simple" || erropt == "") {
      stop(err$error$code, " - ", err$error$msg, call. = FALSE)
    } else {
      stop(err$error$code, " - ", err$error$msg, 
           "\nAPI stack trace\n", 
           pluck_trace(err$error$trace), call. = FALSE)
    }
  }
}

pluck_trace <- function(x) {
  if (is.null(x)) {
    " - no stack trace"
  } else {
    x
  }
}

# POST helper fxn
solr_POST <- function(base, path, body, args, content, ...) {
  invisible(match.arg(args$wt, c("xml", "json", "csv")))
  args <- lapply(args, function(x) if (is.logical(x)) tolower(x) else x)
  cli <- crul::HttpClient$new(url = base, opts = list(...))
  tt <- cli$post(path, query = args, body = body)
  get_response(tt)
}

# POST helper fxn - just a body
solr_POST_body <- function(base, path, body, args, callopts, ...) {
  invisible(match.arg(args$wt, c("xml", "json")))
  httpcli <- crul::HttpClient$new(
    url = base, 
    headers = list(`Content-Type` = "application/json"), opts = callopts)
  res <- httpcli$post(path = path, query = args, body = body, encode = "form")
  if (res$status_code > 201) solr_error(res) else res$parse("UTF-8")
}

# POST helper fxn for R objects
obj_POST <- function(base, path, body, args, ...) {
  invisible(match.arg(args$wt, c("xml", "json", "csv")))
  args <- lapply(args, function(x) if (is.logical(x)) tolower(x) else x)
  body <- jsonlite::toJSON(body, auto_unbox = TRUE)
  cli <- crul::HttpClient$new(
    url = base, 
    headers = list(`Content-Type` = "application/json")
  )
  tt <- cli$post(path, query = args, body = body, encode = "form", ...)
  get_response(tt)
}

# check if core/collection exists, if not stop
stop_if_absent <- function(x) {
  tmp <- vapply(list(core_exists, collection_exists), function(z) {
    tmp <- tryCatch(z(x), error = function(e) e)
    if (inherits(tmp, "error")) FALSE else tmp
  }, logical(1))
  if (!any(tmp)) {
    stop(
      x, 
      " doesn't exist - create it first.\n See core_create()/collection_create()", 
      call. = FALSE)
  }
}

# helper for POSTing from R objects
obj_proc <- function(base, path, body, args, raw, ...) {
  out <- structure(obj_POST(base, path, body, args, ...), class = "update", 
                   wt = args$wt)
  if (raw) {
    out
  } else {
    solr_parse(out) 
  }
}

get_response <- function(x) {
  if (x$status_code > 201) {
    err <- jsonlite::fromJSON(x$parse("UTF-8"))$error
    stop(sprintf("%s: %s", err$code, err$msg), call. = FALSE)
  } else {
    x$parse("UTF-8")
  }
}

# small function to replace elements of length 0 with NULL
replacelen0 <- function(x) {
  if (length(x) < 1) { 
    NULL 
  } else { 
    x 
  }
}
  
sc <- function(l) Filter(Negate(is.null), l)

asl <- function(z) {
  if (is.null(z)) {
    NULL
  } else {
    if (is.logical(z) || tolower(z) == "true" || tolower(z) == "false") {
      if (z) {
        return('true')
      } else {
        return('false')
      }
    } else {
      return(z)
    }
  }
}

docreate <- function(base, path, files, args, content, raw, ...) {
  out <- structure(solr_POST(base, path, files, args, content, ...), 
                   class = "update", wt = args$wt)
  if (raw) return(out)
  solr_parse(out)
}

doatomiccreate <- function(base, path, body, args, content, raw, ...) {
  ctype <- get_ctype(content)
  out <- structure(solr_POST_body(base, path, body, args, ctype, ...), 
                   class = "update", wt = args$wt)
  if (raw) return(out)
  solr_parse(out)
}

objcreate <- function(base, path, dat, args, raw, ...) {
  out <- structure(solr_POST(base, path, dat, args, "json", ...), 
                   class = "update", wt = args$wt)
  if (raw) return(out)
  solr_parse(out)
}

check_conn <- function(x) {
  if (!inherits(x, "solr_connection")) {
    stop("Input to conn parameter must be an object of class solr_connection", 
         call. = FALSE)
  }
  if (is.null(x)) {
    stop("You must provide a connection object", 
         call. = FALSE)
  }
}

check_wt <- function(x) {
  if (!is.null(x)) {
    if (!x %in% c('json', 'xml', 'csv')) {
      stop("wt must be one of: json, xml, csv", 
           call. = FALSE)
    }  
  }
}

check_defunct <- function(...) {
  calls <- names(sapply(match.call(), deparse))[-1]
  calls_vec <- "verbose" %in% calls
  if (any(calls_vec)) {
    stop("The parameter verbose has been removed - see ?solr_connect", 
         call. = FALSE)
  }
}

is_in_cloud_mode <- function(x) {
  xx <- crul::HttpClient$new(url = x$make_url())
  res <- xx$get("solr/admin/collections", 
                query = list(action = 'LIST', wt = 'json'))
  if (res$status_code > 201) return(FALSE)
  msg <- jsonlite::fromJSON(res$parse("UTF-8"))$error$msg
  if (is.null(msg)) return(TRUE)
  !grepl("not running", msg)
}

is_not_in_cloud_mode <- function(x) !is_in_cloud_mode(x)

json_parse <- function(x, raw) {
  if (raw) {
    x
  } else {
    jsonlite::fromJSON(x)
  }
}

unbox_if <- function(x, recursive = FALSE) {
  if (!is.null(x)) {
    if (recursive) {
      rapply(x, jsonlite::unbox, how = "list")
    } else {
      lapply(x, jsonlite::unbox)
    }
  } else {
    NULL
  }
}

`%||%` <- function(x, y) if (suppressWarnings(is.na(x)) || is.null(x)) y else x

url_handle <- function(name) {
  if (is.null(name)) {
    ""
  } else {
    file.path("solr", name, "select")
  }
}
