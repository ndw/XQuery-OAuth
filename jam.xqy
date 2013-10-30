xquery version "0.9-ml"

(:~
 : Mark Logic Interface to Java
 :
 : For a tutorial please see
 : http://xqzone.marklogic.com/howto/tutorials/2006-05-mljam.xqy.
 :
 : Copyright 2006-2007 Jason Hunter and Ryan Grimm
 :
 : Licensed under the Apache License, Version 2.0 (the "License");
 : you may not use this file except in compliance with the License.
 : You may obtain a copy of the License at
 :
 :     http://www.apache.org/licenses/LICENSE-2.0
 :
 : Unless required by applicable law or agreed to in writing, software
 : distributed under the License is distributed on an "AS IS" BASIS,
 : WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 : See the License for the specific language governing permissions and
 : limitations under the License.
 :
 : @author Jason Hunter and Ryan Grimm
 : @version 1.2
 :)

module "http://xqdev.com/jam"
declare namespace jam = "http://xqdev.com/jam"
default function namespace = "http://www.w3.org/2003/05/xpath-functions"

(:~
 : Holds the randomly generated context id for when the user doesn't
 : specify a context id.
 :)
define variable $default-context as xs:string { "" }

(:~
 : Holds the mapping between context ids and web addresses, as setup
 : by the jam:start() function.
 :)
define variable $urlmap as element(urlmap) { <urlmap/> }

(:
 : Private utility function that returns true() if the passed-in string
 : contains only whitespace.  For efficiency it actually only checks the
 : leading 4k of the string.
 :
 : @param $s String to check for whitespace
 : @return true() if the string is all whitespace, false() if not
 :)
define function jam:_is-all-whitespace(
  $s as xs:string
) as xs:boolean
{
  (: OK, we cheat a little so we don't normalize a huge string :)
  normalize-space(substring($s, 0, 4096)) = ""
}

(:~
 : Assigns a variable in the specified remote Java context.  XQuery
 : types are mapped to Java types according to the following table
 : (setting other types generates an error):
 :
 : <table>
 : <tr><td>xs:anyURI</td>                <td>String</td></tr>
 : <tr><td>xs:base64Binary</td>          <td>byte[]</td></tr>
 : <tr><td>xs:boolean</td>               <td>boolean</td></tr>
 : <tr><td>xs:date</td>                  <td>javax.xml.datatype.XMLGregorianCalendar</td></tr>
 : <tr><td>xs:dateTime</td>              <td>javax.xml.datatype.XMLGregorianCalendar</td></tr>
 : <tr><td>xs:decimal</td>               <td>BigDecimal</td></tr>
 : <tr><td>xs:double</td>                <td>double</td></tr>
 : <tr><td>xs:duration</td>              <td>javax.xml.datatype.Duration</td></tr>
 : <tr><td>xs:float</td>                 <td>float</td></tr>
 : <tr><td>xs:gDay</td>                  <td>javax.xml.datatype.XMLGregorianCalendar</td></tr>
 : <tr><td>xs:gMonth</td>                <td>javax.xml.datatype.XMLGregorianCalendar</td></tr>
 : <tr><td>xs:gMonthDay</td>             <td>javax.xml.datatype.XMLGregorianCalendar</td></tr>
 : <tr><td>xs:gYear</td>                 <td>javax.xml.datatype.XMLGregorianCalendar</td></tr>
 : <tr><td>xs:gYearMonth</td>            <td>javax.xml.datatype.XMLGregorianCalendar</td></tr>
 : <tr><td>xs:hexBinary</td>             <td>byte[]</td></tr>
 : <tr><td>xs:int</td>                   <td>int</td></tr>
 : <tr><td>xs:integer</td>               <td>long</td></tr>
 : <tr><td>xs:QName</td>                 <td>javax.xml.namespace.QName</td></tr>
 : <tr><td>xs:string</td>                <td>String</td></tr>
 : <tr><td>xs:time</td>                  <td>javax.xml.datatype.XMLGregorianCalendar</td></tr>
 : <tr><td>xdt:dayTimeDuration</td>      <td>javax.xml.datatype.Duration</td></tr>
 : <tr><td>xdt:untypedAtomic</td>        <td>String</td></tr>
 : <tr><td>xdt:yearMonthDuration</td>    <td>javax.xml.datatype.Duration</td></tr>
 : <tr><td>attribute()</td>              <td>String holding its xdmp:quote() value</td></tr>
 : <tr><td>comment()</td>                <td>String holding its xdmp:quote() value</td></tr>
 : <tr><td>document-node()</td>          <td>String holding its xdmp:quote() value</td></tr>
 : <tr><td>element()</td>                <td>String holding its xdmp:quote() value</td></tr>
 : <tr><td>processing-instruction()</td> <td>String holding its xdmp:quote() value</td></tr>
 : <tr><td>text()</td>                   <td>String holding its xdmp:quote() value</td></tr>
 : <tr><td>binary()</td>                 <td>byte[]</td></tr>
 : <tr><td>()</td>                       <td>null</td></tr>
 : </table>
 :
 : If the XQuery $value holds a sequence of values, it's passed to Java as
 : an Object[] array holding instances of the above types (with primitives
 : autoboxed).
 :
 : If the XQuery $value holds a value mapped to String or byte[] it's sent
 : on the wire in an optimized fashion (not possible when in an array).
 :
 : Note that in XQuery there's no difference between an item and a sequence
 : of length one containing that item.  If you want to assign an XQuery
 : sequence to a Java array and it might be a single item in XQuery, use
 : jam:set-array() or jam:set-array-in().  These pass the value as an array
 : even if the sequence happens to be of length one.
 :
 : @param $var Name of variable to set, must be a legal Java token
 : @param $value Value to assign for the variable
 : @param $context Named context in which to do the assignment, or the
 :   default context if not specified
 :)
define function jam:set-in(
  $var as xs:string,
  $value as item()*,
  $context as xs:string
) as empty()
{
  (: Check for single string optimization. :)
  (: We do this because it takes a full minute per meg to eval() a string
     on my laptop.  This way the BeanShell can receive it directly. :)
  (: Note that sending an array of strings won't be as efficient. :)
  (: If it's all whitespace we have trouble posting, so don't optimize. :)
  if ($value instance of xs:string and
      not(jam:_is-all-whitespace($value))) then
    jam:_call("post", $context, "set-string", $var, $value)

  (: We optimize sending a binary() also :)
  (: We check for xs:hexBinary with describe() because untypedAtomic
     values can be converted wrongly and may contain whitespace that
     messes up the post body (like above). :)
  else if ($value instance of binary() or
              ($value instance of document-node() and
               $value/binary() instance of binary()) or
           starts-with(xdmp:describe($value), "xs:hexBinary")) then
    jam:_call("post", $context, "set-binary", $var,
      xs:string($value)  (: server knows to decode the hexBinary :)
    )

  (: Lastly, we optimize sending a single node, just like a string :)
  else if ($value instance of node()) then
    jam:_call("post", $context, "set-string", $var, xdmp:quote($value))

  (: If we're some other type or an array, create an expression to eval :)
  else
    jam:_call("post", $context, "eval", (), 
      concat('unset("', $var, '"); ', $var, ' = ', jam:_get-java($value), ';')
    )
}

(:~
 : Special form of jam:set-in() that passes the value as a Java array even
 : if it's a sequence of length one.  Java will see the variable as an Object[].
 :
 : @param $var Name of variable to set, must be a legal Java token
 : @param $value Value to assign for the variable
 : @param $context Named context in which to do the assignment, or the
 :   default context if not specified
 :)
define function jam:set-array-in(
  $var as xs:string,
  $value as item()*,
  $context as xs:string
) as empty()
{
  (: Treat $value as an array regardless of its actual length. :)
  jam:_call("post", $context, "eval", (), 
    concat('unset("', $var, '"); ', $var, ' = ', jam:_get-java-array($value), ';')
  )
}

(:
 : Private utility function to support set-array(), by mapping XQuery data types
 : to a Java array expression.
 :)
define function jam:_get-java-array(
  $value as item()*
) as xs:string
{
  concat('new Object[] { ',  (: Might want to choose more specific type :)
    string-join(for $i in $value return jam:_get-java($i), ', ')
  , ' }')
}

(:
 : Private utility function to support set(), by mapping XQuery data types
 : to a Java expression.
 :)
define function jam:_get-java(
  $value as item()*
) as xs:string
{
  if (count($value) > 1) then
    concat('new Object[] { ',  (: Might want to choose more specific type :)
      string-join(for $i in $value return jam:_get-java($i), ', ')
    , ' }')
  else

  if (empty($value)) then
    'null'

  else if ($value instance of xs:string or
           $value instance of xs:anyURI or
           $value instance of xdt:untypedAtomic) then
    concat('"', jam:_escape-string(xs:string($value)), '"')

  else if ($value instance of xs:boolean) then
    string($value)

  else if ($value instance of xs:double) then
    if ($value = xs:double("INF")) then
      'Double.POSITIVE_INFINITY'
    else if ($value = xs:double("-INF")) then
      'Double.NEGATIVE_INFINITY'
    else if (jam:_isNaN($value)) then
      'Double.NaN'
    else
      concat(string($value), 'D')

  else if ($value instance of xs:float) then
    if ($value = xs:float("INF")) then
      'Float.POSITIVE_INFINITY'
    else if ($value = xs:float("-INF")) then
      'Float.NEGATIVE_INFINITY'
    else if (jam:_isNaN($value)) then
      'Float.NaN'
    else
      concat(string($value), 'F')

  else if ($value instance of xs:int) then
    string($value)

  (: Little special handling since ML 3.0 doesn't throw cast errors :)
  else if ($value instance of xs:integer) then
    if ($value <= 9223372036854775807) then
      concat(string($value), 'L')
    else
      concat('new java.math.BigDecimal("', string($value), '")')

  else if ($value instance of xs:decimal) then
    concat('new java.math.BigDecimal("', string($value), '")')

  else if ($value instance of xs:QName) then
    concat('new javax.xml.namespace.QName("',
              get-namespace-from-QName($value), '","',
              get-local-name-from-QName($value), '","',
              substring-before(xs:string($value), ":"), '")')

  (: Note on Xerces and gMonth...
     Xerces doesn't like "--01" as a gMonth but rather "--01--" which is
     erroneous according to http://www.w3.org/2001/05/xmlschema-errata#e2-12.
     We choose to send using the new lexical form, as output by MarkLogic,
     and trust that newer Xerces versions will understand. :)
  else if ($value instance of xs:gDay or
           $value instance of xs:gMonth or  (: gMonth fails on old xerces :)
           $value instance of xs:gYear or
           $value instance of xs:date or
           $value instance of xs:dateTime or
           $value instance of xs:time or
           $value instance of xs:gMonthDay or
           $value instance of xs:gYearMonth) then
    concat('javax.xml.datatype.DatatypeFactory.newInstance()',
           '.newXMLGregorianCalendar("', string($value), '")')

  (: Note on Xerces and durations...
     The Xerces Duration.getXMLSchemaType() method gets confused on
     durations like "P1D" because it thinks only the day value is set
     and thinks that's illegal.  We could fix this by munging the string
     form to be exhaustive, but it doesn't seem to really matter. :)
  else if ($value instance of xs:duration or
           $value instance of xdt:dayTimeDuration or
           $value instance of xdt:yearMonthDuration) then
    concat('javax.xml.datatype.DatatypeFactory.newInstance()',
           '.newDuration("', string($value), '")')

  (: This code assumes a hexdecode() function available in the BeanShell
     context, implemented by something such as this Jakarta Commons class:
       http://svn.apache.org/viewcvs.cgi/jakarta/commons/proper/codec/
       trunk/src/java/org/apache/commons/codec/binary/Hex.java
       ?rev=161350&view=markup :)
  else if ($value instance of binary() or
              ($value instance of document-node() and
               $value/binary() instance of binary()) or
           $value instance of xs:hexBinary) then
    concat('hexdecode("', xs:string($value), '")')

  (: This code assumes a base64decode() function.
     We could convert it in MarkLogic to hexBinary but that's less efficient.
     Plus, MarkLogic built-ins only let you decode to a string, limiting.
     My COS library includes a base64 decoder, as does Jakarta. :)
  else if ($value instance of xs:base64Binary) then
    concat('base64decode("', xs:string($value), '")')

  (: Any other type of node :)
  else if ($value instance of node()) then
    concat('"', jam:_escape-string(xdmp:quote($value)), '"')

  else
    error(concat("Unhandled type: ", xdmp:describe($value)))
}


(:~
 : Executes the given Java code in the specified remote Java context.
 : For execution that returns a value, eval-get-in() may be more optimal.
 : Hint: it's often best to surround the Java code string to evaluate
 : with single quotes rather than double quotes.  Then only single quotes
 : have to be escaped (by writing two single quotes in a row).
 :
 : @param $expr Java expression to evaluate
 : @param $context Named context in which to do the evaluation, or the
 :   default context if not specified
 :)
define function jam:eval-in(
  $expr as xs:string,
  $context as xs:string
) as empty()
{
  jam:_call("post", $context, "eval", (), $expr)
}


(:~
 : Executes the given Java code in the specified remote Java context,
 : and returns the value from last statement evaluated.
 : Hint: it's often best to surround the Java code string to evaluate
 : with single quotes rather than double quotes.  Then only single quotes
 : have to be escaped (by writing two single quotes in a row).
 :
 : @param $expr Java expression to evaluate
 : @param $context Named context in which to do the evaluation, or the
 :   default context if not specified
 : @return The value from the last statement evaluated
 :)
define function jam:eval-get-in(
  $expr as xs:string,
  $context as xs:string
) as item()*
{
  jam:_call("post", $context, "eval-get", (), $expr)
}


(:~
 : Unassigns the named variable from the specified remote Java context.
 :
 : @param $var Name of variable to unset, must be a legal Java token
 : @param $context Named context in which to do the unset, or the
 :   default context if not specified
 :)
define function jam:unset-in(
  $var as xs:string,
  $context as xs:string
) as empty()
{
  jam:_call("post", $context, "unset", $var, ())
}


(:~
 : Retrieves the value of the named parameter from the specified remote
 : Java context.  Java types are mapped to XQuery types according to the
 : following table (getting other types generates an error):
 :
 : <table>
 : <tr><td>byte[]</td>           <td>binary()</td></tr>
 : <tr><td>BigDecimal</td>       <td>xs:decimal</td></tr>
 : <tr><td>boolean</td>          <td>xs:boolean</td></tr>
 : <tr><td>double</td>           <td>xs:double</td></tr>
 : <tr><td>float</td>            <td>xs:float</td></tr>
 : <tr><td>int</td>              <td>xs:int</td></tr>
 : <tr><td>long</td>             <td>xs:integer</td></tr>
 : <tr><td>Date</td>             <td>xs:dateTime</td></tr>
 : <tr><td>String</td>           <td>xs:string</td></tr>
 : <tr><td>JDOM Attribute</td>   <td>attribute()</td></tr>
 : <tr><td>JDOM Comment</td>     <td>comment()</td></tr>
 : <tr><td>JDOM Document</td>    <td>document-node()</td></tr>
 : <tr><td>JDOM Element</td>     <td>element()</td></tr>
 : <tr><td>JDOM PI</td>          <td>processing-instruction()</td></tr>
 : <tr><td>JDOM Text</td>        <td>text()</td><tr>
 : <tr><td>XMLGregorianCalendar</td> <td>xs:dateTime, xs:time, xs:date,
 :                                       xs:gYearmonth, xs:gMonthDay,
 :                                       xs:gYear, xs:gMonth,
 :                                       or xs:gDay depending on
 :                                       getXMLSchemaType()</td></tr>
 : <tr><td>Duration</td>         <td>xs:duration, xdt:dayTimeDuration, or
 :                                   xdt:yearMonthDuration depending on
 :                                   getXMLSchemaType()</td></tr>
 : <tr><td>QName</td>            <td>xs:QName</td></tr>
 : <tr><td>null</td>             <td>()</td></tr>
 : </table>
 :
 : If the Java variable holds an array, it's returned to XQuery as a
 : sequence.
 :
 : If the Java variable holds a String or byte[] it's sent on the wire
 : in an optimized fashion (not possible when in an array).
 :
 : @param $var Name of variable to get, must be a legal Java token
 : @param $context Named context from which to do the get, or the
 :   default context if not specified
 :)
define function jam:get-in(
  $var as xs:string,
  $context as xs:string
) as item()*
{
  jam:_call("get", $context, "get", $var, ())
}


(:~
 : Enables JAM usage by creating a mapping between a web address and a
 : context id.  Later calls to the named context will connect to the given
 : web address for execution.  This function allows the same XQuery to
 : connect to multiple different servers, and manage multiple contexts on
 : each.  This function does all its work locally and does not actually
 : connect to the given web address.
 :
 : @param $url Web address to communicate with for the given context
 : @param $user Login username to use on server, or () if none
 : @param $pass Login password to use on server, or () if none
 : @param $context Name of the context
 :)
define function jam:start-in(
  $url as xs:string,
  $user as xs:string?,
  $pass as xs:string?,
  $context as xs:string
) as empty()
{
  (:
    The urlmap looks like this:
      <urlmap>
        <host context="12345">
          <url>http://localhost:8080/jam</url>
          <user>admin</user>
          <pass>secret</pass>
        </host>
        <host context="open">
          <url>http://localhost:8080/jam</url>
          <user></user>
          <pass></pass>
        </host>
      </urlmap>
  :)
  xdmp:set($urlmap,
    <urlmap>
      { $urlmap/host except $urlmap/host[@context = $context] }
      <host context="{$context}">
        <url>{$url}</url>
        <user>{$user}</user>
        <pass>{$pass}</pass>
      </host>
    </urlmap>)
}


(:~
 : Allows the Java server to reclaim the resources associated w/ the 
 : specified remote Java context.  Should be called at the end of each
 : XQuery unless the context needs to persist into other queries.
 : If not called, the server does periodic sweeps to end contexts
 : that haven't been touched within some period of time.
 :
 : @param $context Named context whose resources can be freed
 :)
define function jam:end-in(
  $context as xs:string
) as empty()
{
  jam:_call("post", $context, "end", (), ())
}


(:~
 : Returns the content that's been written to standard out in the specified
 : remote Java context.  Each call clears the buffer.  For efficiency reasons
 : only the last 10k of content is retained.  Only captures output
 : from print(), not System.out.println() due to BeanShell limitations.
 :
 : @param $context Named context whose stdout should be retrieved
 : @return The latest standard out output
 :)
define function jam:get-stdout-in(
  $context as xs:string
) as xs:string
{
  jam:_call("get", $context, "get-stdout", (), ())
}


(:~
 : Returns the content that's been written to standard error in the specified
 : remote Java context.  Each call clears the buffer.  For efficiency reasons
 : only the last 10k of content is retained.  Only captures output
 : from error(), not System.err.println() due to BeanShell limitations.
 :
 : @param $context Named context whose stdout should be retrieved
 : @return The latest standard error output
 :)
define function jam:get-stderr-in(
  $context as xs:string
) as xs:string
{
  jam:_call("get", $context, "get-stderr", (), ())
}


(:~
 : Loads the named BeanShell source file, for loading useful functions.
 : Beware the source file is relative to the server, not the client.
 : Also beware windows paths should begin with the drive letter.
 :
 : @param $bsh File path from which to load a supporting .bsh script
 : @param $context Named context whose stdout should be retrieved
 :)
define function jam:source-in(
  $bsh as xs:string,
  $context as xs:string
) as empty()
{
  jam:_call("post", $context, "source", $bsh, ())
}


(:
 : Private function to return the random context id for this XQuery
 : context.  Once generated, values are held in $default-context.
 :)
define function jam:_get-default-context() as xs:string
{
  (: We'll let random numbers work for now :)
  if ($default-context = "")
    then xdmp:set($default-context, concat("temp:", xs:string(xdmp:random())))
    else (),
  $default-context
}

(:
 : Private function that handles the HTTP work necessary to communicate
 : between XQuery and the remote Java context.
 :)
define function jam:_call(
  $method as xs:string,  (: get or post :)
  $context as xs:string,
  $verb as xs:string,
  $name as xs:string?,
  $body as xs:string?
) as item()*
{
  let $base := string($urlmap/host[@context = $context]/url)
  return
  if ($base = "") then error(concat("Uninitialized context: ", $context)) else

  let $user := string($urlmap/host[@context = $context]/user)
  let $pass := string($urlmap/host[@context = $context]/pass)
  let $authentication :=
    if ($user != "" and $pass != "") then
      <authentication xmlns="xdmp:http" method="basic">
        <username>{$user}</username>
        <password>{$pass}</password>
      </authentication>
    else if ($user = "" and $pass = "") then
      ()
    else if ($user = "") then
      error("Credentials corrupt, cannot have password without user")
    else 
      error("Credentials corrupt, cannot have user without password")

  (: We check body = "" to enable set("x", "") calls to empty post :)
  let $options := 
    if (empty($body) or $body = "") then
      <options xmlns="xdmp:http">
        { $authentication }
        <timeout>10</timeout>
      </options>
    else
      (: Design bug: ML requires non-whitespace text :)
      <options xmlns="xdmp:http">
        { $authentication }
        <timeout>30</timeout> 
        <headers><content-type>text/plain; charset=UTF-8</content-type></headers>
        <data>{$body}</data>
      </options>

  let $url := concat($base, "/", $context, "/", $verb,
       if (string-length($name) > 0) then
         concat("?name=", xdmp:url-encode($name))
       else
         "")

  let $response :=
    if (lower-case($method) = "get") then
      xdmp:http-get($url, $options)
    else if (lower-case($method) = "post") then
      xdmp:http-post($url, $options)
    else error(concat("Unrecognized method: ", $method))

  let $code := xs:integer($response[1]/*:code)
  return
  if ($code = 204) then (: no content :)
    ()
  else if ($code = 200) then
    if (starts-with(string($response[1]//*:headers/*:content-type),
                                             "x-marklogic/xquery")) then
      (
        (: xdmp:log(xdmp:quote($response[2]/binary())), :)
        xdmp:eval(xdmp:quote($response[2]/binary()))
      )
    else
      let $ans := $response[2]/(binary()|text()|*) (: thing under doc node :)
      return
      if ($ans instance of text()) then xdmp:quote($ans) else $ans
      (: Had xs:string($ans) but there's a bug that it returned an old value :)
  else
    error($response[2]) (: wish cq did a better job with this :)
}

(:
 : Private function that escapes an XQuery string such that it can be
 : evaluated in a Java context as a string.  Escapes backslashes, double
 : quotes, and newlines.
 :)
define function jam:_escape-string(
  $s as xs:string
) as xs:string
{
  (: These replaces funny because arg2 is a regexp and arg3 is a literal :)
  let $s := replace($s, '\\', '\\\\') (: \ replaced with \\ :)
  let $s := replace($s, '"', '\\"')  (: " replaced with \" :)
  let $s := replace($s, '&#xA;', '\\n')
  return $s
}

(:
 : Private function that checks if a value is NaN (not a number).
 :)
define function jam:_isNaN(
  $x
) as xs:boolean
{
  not($x <= 0) and not($x >= 0)
}





(: Default context functions, that all pass through to *-in varieties :)

define function jam:set(
  $var as xs:string,
  $value as item()*
) as empty()
{
  jam:set-in($var, $value, jam:_get-default-context())
}

define function jam:set-array(
  $var as xs:string,
  $value as item()*
) as empty()
{
  jam:set-array-in($var, $value, jam:_get-default-context())
}

define function jam:eval(
  $expr as xs:string
) as empty()
{
  jam:eval-in($expr, jam:_get-default-context())
}

define function jam:eval-get(
  $expr as xs:string
) as item()*
{
  jam:eval-get-in($expr, jam:_get-default-context())
}

define function jam:unset(
  $var as xs:string
) as empty()
{
  jam:unset-in($var, jam:_get-default-context())
}

define function jam:get(
  $var as xs:string
) as item()*
{
  jam:get-in($var, jam:_get-default-context())
}

define function jam:start(
  $url as xs:string,
  $user as xs:string?,
  $pass as xs:string?
) as empty()
{
  jam:start-in($url, $user, $pass, jam:_get-default-context())
}

define function jam:end() as empty()
{
  jam:end-in(jam:_get-default-context())
}

define function jam:get-stdout() as xs:string
{
  jam:get-stdout-in(jam:_get-default-context())
}

define function jam:get-stderr() as xs:string
{
  jam:get-stderr-in(jam:_get-default-context())
}

define function jam:source(
  $bsh as xs:string
) as empty()
{
  jam:source-in($bsh, jam:_get-default-context())
}

