xquery version "1.0-ml";

module namespace oa="http://marklogic.com/ns/oauth";

declare namespace xh="xdmp:http";

declare default function namespace "http://www.w3.org/2005/xpath-functions";

declare option xdmp:mapping "false";

(:
  let $service :=
     <oa:service-provider realm="">
       <oa:request-token>
         <oa:uri>http://twitter.com/oauth/request_token</oa:uri>
         <oa:method>GET</oa:method>
       </oa:request-token>
       <oa:user-authorization>
         <oa:uri>http://twitter.com/oauth/authorize</oa:uri>
       </oa:user-authorization>
       <oa:user-authentication>
         <oa:uri>http://twitter.com/oauth/authenticate</oa:uri>
         <oa:additional-params>force_login=true</oa:additional-params>
       </oa:user-authentication>
       <oa:access-token>
         <oa:uri>http://twitter.com/oauth/access_token</oa:uri>
         <oa:method>POST</oa:method>
       </oa:access-token>
       <oa:signature-methods>
         <oa:method>HMAC-SHA1</oa:method>
       </oa:signature-methods>
       <oa:oauth-version>1.0</oa:oauth-version>
       <oa:authentication>
         <oa:consumer-key>YOUR-CONSUMER-KEY</oa:consumer-key>
         <oa:consumer-key-secret>YOUR-CONSUMER-SECRET</oa:consumer-key-secret>
       </oa:authentication>
     </oa:service-provider>
:)

declare function oa:timestamp() as xs:unsignedLong {
  let $epoch := xs:dateTime('1970-01-01T00:00:00Z')
  let $now := current-dateTime()
  let $d := $now - $epoch
  let $seconds
    := 86400 * days-from-duration($d)
      + 3600 * hours-from-duration($d)
        + 60 * minutes-from-duration($d)
             + seconds-from-duration($d)
  return
    xs:unsignedLong($seconds)
};

declare function oa:sign($key as xs:string, $data as xs:string) as xs:string {
	xdmp:hmac-sha1($key, $data, "base64")
};

declare function oa:signature-method(
  $service as element(oa:service-provider)
) as xs:string
{
  if ($service/oa:signature-methods/oa:method = "HMAC-SHA1")
  then "HMAC-SHA1"
  else error(xs:QName("oa:BADSIGMETHOD"),
            "Service must support 'HMAC-SHA1' signatures.")
};

declare function oa:http-method(
  $proposed-method as xs:string
) as xs:string
{
  if (upper-case($proposed-method) = "GET")
  then "GET"
  else if (upper-case($proposed-method) = "POST")
  then "POST"
    else error(xs:QName("oa:BADHTTPMETHOD"),
               "Service must use HTTP GET or POST.")
};

declare function oa:request-token(
  $service as element(oa:service-provider),
  $callback as xs:string?)
as element(oa:request-token)
{
  let $options := if (empty($callback))
                  then ()
                  else
                    <oa:options>
                      <oauth_callback>{$callback}</oauth_callback>
                    </oa:options>
  let $data
    := oa:signed-request($service,
                         $service/oa:request-token/oa:method,
                         $service/oa:request-token/oa:uri,
                         $options, (), ())
  return
    <oa:request-token>
      { if ($data/oa:error)
        then
          $data/*
        else
          for $pair in tokenize($data, "&amp;")
          return
            element { concat("oa:", substring-before($pair, '=')) }
                    { substring-after($pair, '=') }
      }
    </oa:request-token>
};

declare function oa:access-token(
  $service as element(oa:service-provider),
  $request as element(oa:request-token),
  $verifier as xs:string)
as element(oa:access-token)
{
  let $options := <oa:options><oauth_verifier>{$verifier}</oauth_verifier></oa:options>
  let $data
    := oa:signed-request($service,
                         $service/oa:access-token/oa:method,
                         $service/oa:access-token/oa:uri,
                         $options,
                         $request/oa:oauth_token,
                         $request/oa:oaauth_token_secret)
  return
    <oa:access-token>
      { if ($data/oa:error)
        then
          $data/*
        else
          for $pair in tokenize($data, "&amp;")
          return
            element { concat("oa:", substring-before($pair, '=')) }
                    { substring-after($pair, '=') }
      }
    </oa:access-token>
};

declare function oa:signed-request(
  $service as element(oa:service-provider),
  $method as xs:string,
  $serviceuri as xs:string,
  $options as element(oa:options)?,
  $token as xs:string?,
  $secret as xs:string?)
as element(oa:response)
{
  let $realm      := string($service/@realm)
  let $noncei     := xdmp:hash64(concat(current-dateTime(),string(xdmp:random())))
  let $nonce      := xdmp:integer-to-hex($noncei)
  let $stamp      := oa:timestamp()
  let $key        := string($service/oa:authentication/oa:consumer-key)
  let $sigkey     := concat($service/oa:authentication/oa:consumer-key-secret,
                            "&amp;", if (empty($secret)) then "" else $secret)
  let $version    := string($service/oa:oauth-version)
  let $sigmethod  := oa:signature-method($service)
  let $httpmethod := oa:http-method($method)

  let $sigstruct
    := <oa:signature-base-string>
         <oauth_consumer_key>{$key}</oauth_consumer_key>
         <oauth_nonce>{$nonce}</oauth_nonce>
         <oauth_signature_method>{$sigmethod}</oauth_signature_method>
         <oauth_timestamp>{$stamp}</oauth_timestamp>
         <oauth_version>{$version}</oauth_version>
         { if (not(empty($token)))
           then <oauth_token>{$token}</oauth_token>
           else ()
         }
         { if (not(empty($options)))
           then $options/*
           else ()
         }
       </oa:signature-base-string>

  let $encparams
    := for $field in $sigstruct/*
       order by local-name($field)
       return
         concat(local-name($field), "=", encode-for-uri(string($field)))

  let $sigbase := string-join(($httpmethod, encode-for-uri($serviceuri),
                               encode-for-uri(string-join($encparams,"&amp;"))), "&amp;")

  let $signature := encode-for-uri(oa:sign($sigkey, $sigbase))

  (: This is a bit of a pragmatic hack, what is the real answer? :)
  let $authfields := $sigstruct/*[starts-with(local-name(.), "oauth_")
                                  and not(self::oauth_callback)]

  let $authheader := concat("OAuth realm=&quot;", $service/@realm, "&quot;, ",
                            "oauth_signature=&quot;", $signature, "&quot;, ",
                            string-join(
                              for $field in $authfields
                              return
                                concat(local-name($field),"=&quot;", encode-for-uri($field), "&quot;"),
                              ", "))

   let $uriparam := for $field in $options/*
                    return
                      concat(local-name($field),"=",encode-for-uri($field))

   (: This strikes me as slightly weird. Twitter wants the parameters passed
      encoded in the URI even for a POST. I don't know if that's a Twitter
      quirk or the natural way that OAuth apps work. Anyway, if you find
      this library isn't working for some other OAuth'd API, you might want
      to play with this bit.

   let $requri   := if ($httpmethod = "GET")
                    then concat($serviceuri,
                                if (empty($uriparam)) then ''
                                else concat("?",string-join($uriparam,"&amp;")))
                    else $serviceuri

   let $data     := if ($httpmethod = "POST" and not(empty($uriparam)))
                    then <xh:data>{string-join($uriparam,"&amp;")}</xh:data>
                    else ()
   :)

   let $requri   := concat($serviceuri,
                           if (empty($uriparam)) then ''
                           else concat("?",string-join($uriparam,"&amp;")))

   let $data     := ()

   let $options  := <xh:options>
                      <xh:headers>
                        <xh:Authorization>{$authheader}</xh:Authorization>
                      </xh:headers>
                      { $data }
                    </xh:options>

   let $tokenreq := if ($httpmethod = "GET")
                    then xdmp:http-get($requri, $options)
                    else xdmp:http-post($requri, $options)

   (:
   let $trace := xdmp:log(concat("requri: ", $requri))
   let $trace := xdmp:log(concat("sigbse: ", $sigbase))
   let $trace := xdmp:log($options)
   let $trace := xdmp:log($tokenreq)
   :)

  return
    <oa:response>
      { if (string($tokenreq[1]/xh:code) != "200")
        then
          (<oa:error>{$tokenreq[1]}</oa:error>,
           <oa:error-body>{$tokenreq[2]}</oa:error-body>)
        else
          $tokenreq[2]
      }
    </oa:response>
};
