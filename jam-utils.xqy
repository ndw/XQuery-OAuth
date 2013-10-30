xquery version "0.9-ml"

(:~
 : Library of utility functions written on top of MLJAM
 :
 : For a tutorial please see
 : http://xqzone.marklogic.com/howto/tutorials/2006-05-mljam.xqy.
 :
 : Copyright 2006 Jason Hunter
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
 : @version 1.0
 :)

module "http://xqdev.com/jam-utils"
declare namespace jamu = "http://xqdev.com/jam-utils"
default function namespace = "http://www.w3.org/2003/05/xpath-functions"

import module namespace jam="http://xqdev.com/jam" at "jam.xqy"

(: Later on I'll probably make these all take an optional second arg
   context name, esp since 3.1 will allow optional args :)

(: metadata should take node, so should xslfo :)


(:~
 : Returns the MD5 hash of the specified string, as a hex encoded string.
 : Leverates Java's java.security.MessageDigest class.
 :
 : Depends on jam:start() having previously been called.
 :
 : @param $x The string on which to do the MD5 hash
 : @return The MD5 hash of the given string
 :)
define function jamu:encrypt($algorithm as xs:string, $key as xs:string, $data as xs:string, $output as xs:string) as xs:string
{
  (: I use eval-get() to reduce the net hit count by one :)
  (: I surround the Java with curly braces and declare all variable types 
     even though it's optional in order to limit the variable scope to this
     context and reduce the chances for collision. :)
  jam:set("algorithm", $algorithm),
  jam:set("key", $key),
  jam:set("data", $data),
  jam:set("output", $output),
  xs:string(
    jam:eval-get('{
		import nl.daidalos.util.Encryption;
		
		Encryption.encrypt(Encryption.Algorithm.getByName(algorithm), key, data, Encryption.Output.getByName(output));
    }')
  )
}

(:~
 : Returns the MD5 hash of the specified string, as a hex encoded string.
 : Leverates Java's java.security.MessageDigest class.
 :
 : Depends on jam:start() having previously been called.
 :
 : @param $x The string on which to do the MD5 hash
 : @return The MD5 hash of the given string
 :)
define function jamu:md5($x as xs:string) as xs:string
{
  (: I use eval-get() to reduce the net hit count by one :)
  (: I surround the Java with curly braces and declare all variable types 
     even though it's optional in order to limit the variable scope to this
     context and reduce the chances for collision. :)
  jam:set("md5src", $x),
  xs:string(
    jam:eval-get('{
        java.security.MessageDigest digest =
          java.security.MessageDigest.getInstance("MD5");
        digest.digest(md5src.getBytes("UTF-8"));
    }')
  )
}

(:~
 : Returns the MD5 hash of the specified binary(), as a hex encoded string.
 : Leverates Java's java.security.MessageDigest class.
 :
 : Depends on jam:start() having previously been called.
 :
 : @param $x The binary() node on which to do the MD5 hash
 : @return The MD5 hash of the given string
 :)
define function jamu:md5-binary($x as binary()) as xs:string
{
  jam:set("md5src", $x),
  xs:string(
    jam:eval-get('{
        java.security.MessageDigest digest =
          java.security.MessageDigest.getInstance("MD5");
        digest.digest(md5src);
    }')
  )
}




(:~
 : Returns the metadata held within the given image, as an XML
 : &lt;metadata&gt; element holding &lt;directory&gt; elements
 : each of which holds numerous &lt;tag&gt; elements.  Example output:
 :
 : &lt;exif&gt;
 :   &lt;metadata&gt;
 :     &lt;directory name="Exif"&gt;
 :       &lt;tag name="Make"&gt;Canon&lt;/tag&gt;
 :       &lt;tag name="Model"&gt;Canon EOS D30&lt;/tag&gt;
 :       &lt;tag name="Date/Time"&gt;2002:07:04 19:02:52&lt;/tag&gt;
 :       ...
 :     &lt;/directory&gt;
 :     &lt;directory name="Canon Makernote"&gt;
 :       &lt;tag name="Macro Mode"&gt;Normal&lt;/tag&gt;
 :       &lt;tag name="Self Timer Delay"&gt;Self timer not used&lt;/tag&gt;
 :       &lt;tag name="Focus Mode"&gt;One-shot&lt;/tag&gt;
 :       ...
 :     &lt;/directory&gt;
 :     &lt;directory name="Jpeg"&gt;
 :       &lt;tag name="Data Precision"&gt;8 bits&lt;/tag&gt;
 :       &lt;tag name="Image Height"&gt;1080 pixels&lt;/tag&gt;
 :       &lt;tag name="Image Width"&gt;720 pixels&lt;/tag&gt;
 :       ...
 :     &lt;/directory&gt;
 :   &lt;/metadata&gt;
 : &lt;/exif&gt;
 :
 : Leverates the public domain com.drew.metadata Java library.
 :
 : Depends on jam:start() having previously been called.
 :
 : @param $img The binary() node holding the image to investigate
 : @return An XML metadata element
 :)
define function jamu:get-jpeg-metadata($img as binary()) as element(metadata)
{
  jam:set("exifimg", $img),
  jam:eval-get('{

    import com.drew.metadata.*;
    import com.drew.metadata.exif.*;
    import com.drew.imaging.jpeg.*;
    import org.jdom.Element;
    import java.util.*;

    InputStream in = new ByteArrayInputStream(exifimg);
    Metadata jmr = JpegMetadataReader.readMetadata(in);
    Iterator directories = jmr.getDirectoryIterator();

    Element exif = new Element("metadata");
    while (directories.hasNext()) {
        Directory directory = (Directory)directories.next();
        Element dir = new Element("directory");
        dir.setAttribute("name", directory.getName());
        exif.addContent(dir);
        Iterator tags = directory.getTagIterator();
        while (tags.hasNext()) {
            Tag tag = (Tag)tags.next();
            Element t = new Element("tag");
            dir.addContent(t);
            t.setAttribute("name", tag.getTagName());
            t.setText(tag.getDescription());
        }
    }
    exif;  // return this

  }')
}


(:~
 : Applies the specified XSLT stylesheet against the given node and
 : returns the result as a document (or within a document).  The processing
 : takes place in the remote Java context using JAXP and TrAX.
 : Callers are advised to set
 : &lt;xsl:output method="xml" encoding="UTF-8"/&gt;.
 : Beware that because the stylesheet is passed in as an argument, the sheet
 : will not be able to pull on external resources.
 :
 : Depends on jam:start() having previously been called.
 :
 : Note: Some JAXP engines seem to have problems handling PIs in that it
 : forgets to add the second questoin mark.
 :
 : @param $node The node on which to do the transform
 : @param $sheet The stylesheet to apply
 : @return A document result from the transformation
 :)
define function jamu:xslt-sheet($node as node(), $sheet as element())
as document-node()
{
  jam:set("xsltnode", $node),
  jam:set("xsltsheet", $sheet),

  let $retval :=
  jam:eval-get('{

    import javax.xml.transform.*;
    import javax.xml.transform.stream.StreamSource;
    import javax.xml.transform.stream.StreamResult;

    Templates templates = 
      TransformerFactory.newInstance().newTemplates(
                           new StreamSource(
                           new StringReader(xsltsheet)));

    StreamSource source = new StreamSource(
                          new StringReader(xsltnode));

    ByteArrayOutputStream baos = new ByteArrayOutputStream(10240);
    StreamResult result = new StreamResult(baos);

    templates.newTransformer().transform(source, result);
    baos.toByteArray();  // return this

  }')
  return xdmp:unquote(xdmp:quote($retval))
}




(:
 : Private utility function to support all the image resize and convert
 : functions.
 :)
define function jamu:_image-manipulate(
  $img as node(),
  $format as xs:string?,
  $width as xs:integer?,
  $height as xs:integer?,
  $maxWidth as xs:integer?,
  $maxHeight as xs:integer?,
  $percent as xs:integer?
) as binary()
{
  if (not($format = ("png", "jpg", "jpeg", "bmp"))) then
    error(concat("Java 5 supports image manipulation output formats png, jpg, and bmp; cannot process: ", $format))
  else (),

  if ($img instance of binary()) then
    jam:set("imgbefore", $img)
  else if ($img/binary() instance of binary()) then
    jam:set("imgbefore", $img/binary())
  else
    error("Node to image manipulation must be binary() or doc containing binary()"),
    
  jam:set("format", $format),
  jam:set("width", $width),
  jam:set("height", $height),
  jam:set("maxWidth", $maxWidth),
  jam:set("maxHeight", $maxHeight),
  jam:set("percent", $percent),

  jam:eval-get('{

    import java.awt.*;
    import java.awt.image.*;
    import javax.imageio.*;
    import javax.imageio.stream.*;

    BufferedImage image = ImageIO.read(new ByteArrayInputStream(imgbefore));
    if (image == null) {
      throw new RuntimeException("Invalid image content");
    }

    // Use double to force floating point math
    double origWidth = image.getWidth();
    double origHeight = image.getHeight();

    // Now calculate new dimensions depending on passed-in values
    double newWidth = origWidth;
    double newHeight = origHeight;

    // Note: xs:integer makes long
    // Note: Specify just width or height -> keep aspect ratio

    // First, a maxWidth is like a width except it only applies
    // when the width exceeds the max.
    if (maxWidth != null && maxHeight == null) {
      if (maxWidth < origWidth) width = maxWidth;
    }
    else if (maxHeight != null && maxWidth == null) {
      if (maxHeight < origHeight) height = maxHeight;
    }
    else if (maxHeight != null && maxWidth != null) {
      if (maxHeight < origHeight && maxWidth >= origWidth) {
        height = maxHeight;  // only height max matters
      }
      else if (maxWidth < origWidth && maxHeight >= origHeight) {
        width = maxWidth;  // only width max matters
      }
      else if (maxWidth < origWidth && maxHeight < origHeight) {
        // Both matter, find the biggest ratio to know which to use.
        double widthRatio = origWidth / maxWidth;
        double heightRatio = origHeight / maxHeight;
        if (widthRatio > heightRatio) {
          width = maxWidth;
        }
        else {
          height = maxHeight;
        }
      }
    }

    // Now apply the width/height math.  Includes max work above.
    if (width != null && height == null) {
      newWidth = width;
      newHeight = -1;     // newWidth * origHeight / origWidth;
    }
    else if (height != null && width == null) {
      newHeight = (int) height;
      newWidth = -1;      // newHeight * origWidth / origHeight;
    }
    else if (width != null && height != null) {
      newWidth = (int) width;
      newHeight = (int) height;
    }

    if (percent != null) {
      newHeight = (int) Math.ceil(origHeight * percent / 100.0);
      newWidth = (int) Math.ceil(origWidth * percent / 100.0);
    }

    Image scaledImage = image.getScaledInstance(
       (int)newWidth, (int)newHeight, 0);

    BufferedImage bi = new BufferedImage(scaledImage.getWidth(null),
            scaledImage.getHeight(null), BufferedImage.TYPE_INT_RGB);
    Graphics g = bi.createGraphics();
    g.drawImage(scaledImage, 0, 0, null);

    ByteArrayOutputStream baos = new ByteArrayOutputStream(10240);
    ImageIO.write(bi, format, baos);

    g.dispose();  // takes a bit of time to call but safer
    baos.toByteArray();  // return this

  }')
}


(:~
 : Returns a copy of the given image that's been converted to the specified
 : format.  Java 5 supports the output formats "png", "jpg/jpeg", and "bmp".
 : Leverages Java's ImageIO class.
 : The image can be specified as either a binary() node or a
 : document-node() holding a binary() node.
 :
 : Depends on jam:start() having previously been called.
 :
 : @param $img A binary() node holding the image to convert
 : @param $format One of "png", "jpg/jpeg", or "bmp"
 : @return A binary() node holding the converted image
 :)
define function jamu:image-convert(
  $img as node(),
  $format as xs:string)
as binary()
{
  jamu:_image-manipulate($img, $format, (), (), (), (), ())
}

(:~
 : Returns a copy of the given image that's been resized to the specified
 : (integer) percent size of its original and written to the specified format.
 : Java 5 supports the output formats "png", "jpg/jpeg", and "bmp".
 : Leverages Java's ImageIO class.
 : The image can be specified as either a binary() node or a
 : document-node() holding a binary() node.
 :
 : Depends on jam:start() having previously been called.
 :
 : @param $img A binary() node holding the image to convert
 : @param $percent The size of the new image as a percent of the original
 : @param $format One of "png", "jpg/jpeg", or "bmp"
 : @return A binary() node holding the converted image
 :)
define function jamu:image-resize-percent(
  $img as node(),
  $percent as xs:integer,
  $format as xs:string?)
as binary()
{
  jamu:_image-manipulate($img, $format, (), (), (), (), $percent)
}

(:~
 : Returns a copy of the given image that's been resized to the specified
 : pixel sizes and written to the specified format.  If just a width or
 : height is given, it means to resize by preserving the aspect ratio.
 : Java 5 supports the output formats "png", "jpg/jpeg", and "bmp".
 : Leverages Java's ImageIO class.
 : The image can be specified as either a binary() node or a
 : document-node() holding a binary() node.
 :
 : Depends on jam:start() having previously been called.
 :
 : @param $img A binary() node holding the image to convert
 : @param $w The new width of the image, or if unspecified allow to float
 :           based on the specified height
 : @param $h The new height of the image, or if unspecified allow to float
 :           based on the specified width
 : @param $format One of "png", "jpg/jpeg", or "bmp"
 : @return A binary() node holding the converted image
 :)
define function jamu:image-resize-exact(
  $img as node(),
  $w as xs:integer?,
  $h as xs:integer?,
  $format as xs:string?)
as binary()
{
  jamu:_image-manipulate($img, $format, $w, $h, (), (), ())
}

(:~
 : Returns a copy of the given image that's been resized to completely fit
 : within the given pixel sizes, and that's been written to the specified
 : format.  If the width or height is not given, it means no limit need
 : apply.  The aspect ratio is always preserved.
 : Java 5 supports the output formats "png", "jpg/jpeg", and "bmp".
 : Leverages Java's ImageIO class.
 : The image can be specified as either a binary() node or a
 : document-node() holding a binary() node.
 :
 : Depends on jam:start() having previously been called.
 :
 : @param $img A binary() node holding the image to convert
 : @param $w The maximum width of the new image
 : @param $h The maximum height of the new image
 : @param $format One of "png", "jpg/jpeg", or "bmp"
 : @return A binary() node holding the converted image
 :)
define function jamu:image-resize-max(
  $img as node(),
  $w as xs:integer?,
  $h as xs:integer?,
  $format as xs:string?)
as binary()
{
  jamu:_image-manipulate($img, $format, (), (), $w, $h, ())
}


(:~
 : Returns a PDF generated from the given XSL-FO element using the Apache
 : FOP 0.92 engine.
 :
 : Depends on jam:start() having previously been called.
 :
 : @param $xslfo The XSL-FO element to render as PDF
 : @return A binary() node holding the generated PDF document
 :)
define function jamu:fop(
  $xslfo as element()
)
as binary()
{
  (: Takes about 1.5 secs to handle a 28 page PDF of a book chapter.
     Nearly all that time is in the transform() call. :)
  jam:set("xslfo", $xslfo),
  jam:eval-get('{

    import org.apache.fop.apps.*;
    import javax.xml.transform.*;
    import javax.xml.transform.sax.SAXResult;
    import javax.xml.transform.stream.StreamSource;
    import org.xml.sax.*;

    Transformer trans = TransformerFactory.newInstance().newTransformer();

    Source source = new StreamSource(new StringReader(xslfo));

    FopFactory fopFactory = FopFactory.newInstance();
    ByteArrayOutputStream baos = new ByteArrayOutputStream(10240);
    Fop fop = fopFactory.newFop(MimeConstants.MIME_PDF, baos);

    Result res = new SAXResult(fop.getDefaultHandler());
    trans.transform(source, res);

    baos.toByteArray();  // return this

  }')
}
