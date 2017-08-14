package PDF::Builder;

use strict;
no warnings qw[ deprecated recursion uninitialized ];

# $VERSION defined here so developers can run PDF::Builder from git.
# it should be automatically updated as part of the CPAN build.
our $VERSION = '3.005'; # VERSION
my $LAST_UPDATE = '3.006'; # manually update whenever code is changed

use Carp;
use Encode qw(:all);
use FileHandle;

use PDF::Builder::Basic::PDF::Utils;
use PDF::Builder::Util;

use PDF::Builder::Basic::PDF::File;
use PDF::Builder::Basic::PDF::Pages;
use PDF::Builder::Page;

use PDF::Builder::Resource::XObject::Form::Hybrid;

use PDF::Builder::Resource::ExtGState;
use PDF::Builder::Resource::Pattern;
use PDF::Builder::Resource::Shading;

use PDF::Builder::NamedDestination;

use Scalar::Util qw(weaken);

our @FontDirs = ( (map { "$_/PDF/Builder/fonts" } @INC),
                  qw[ /usr/share/fonts /usr/local/share/fonts c:/windows/fonts c:/winnt/fonts ] );

=head1 NAME

PDF::Builder - Facilitates the creation and modification of PDF files

=head1 SYNOPSIS

    use PDF::Builder;

    # Create a blank PDF file
    $pdf = PDF::Builder->new();

    # Open an existing PDF file
    $pdf = PDF::Builder->open('some.pdf');

    # Add a blank page
    $page = $pdf->page();

    # Retrieve an existing page
    $page = $pdf->openpage($page_number);

    # Set the page size
    $page->mediabox('Letter');

    # Add a built-in font to the PDF
    $font = $pdf->corefont('Helvetica-Bold');

    # Add an external TTF font to the PDF
    $font = $pdf->ttfont('/path/to/font.ttf');

    # Add some text to the page
    $text = $page->text();
    $text->font($font, 20);
    $text->translate(200, 700);
    $text->text('Hello World!');

    # Save the PDF
    $pdf->saveas('/path/to/new.pdf');

=head1 A NOTE ON STRINGS (CHARACTER TEXT)

Perl, and hence PDF::Builder, use strings that support the full range of
Unicode characters. When importing strings into a Perl program, for example
by reading text from a file, you must always decode the text from
external encoding (ASCII, UTF-8, Latin-1, ...) into the Perl (internal)
encoding. See pragma C<utf8> and module C<Encode> for details about decoding
text. 

Then, there is the matter of encoding I<output> to match up with available font
character sets. Many fonts (for Latin-alphabet languages) for PDF use appear to 
use WinAnsiEncoding as their default, which is more-or-less Windows CP-1252 (a
superset of ISO-8859-1 Latin-1). Be aware of such encodings when planning how
you're going to output text to a PDF. See C<corefont> and C<psfont> in 
L<FONT METHODS> for additional information.

External text data in various encodings B<< -> >>
Perl internal string representation (Latin-1 or UTF-8) B<< -> >>
Output text data encoded for compatibility with various font files (corefont 
and psfont single byte encodings, TTF/OTF single or multibyte encodings)

=head2 Some Internal Details

Perl (and PDF::Builder) internally use strings which are either ISO-8859-1 or 
UTF-8 encoded (there is an internal flag marking the string as UTF-8 or not). 
If you work I<strictly> in ASCII, with no Latin-1, CP-1252, or
other non-ASCII characters in your text, you should be OK in not doing anything
special about your string encoding. However, any string containing non-ASCII
characters (0x80 or higher) should for safety be converted to the Perl UTF-8
internal representation, via C<$string = Encode::decode(MY_ENCODING, $input);>.
C<MY_ENCODING> would be a string like 'latin1', 'cp-1252', 'utf8', etc. Similar 
capabilities are available for declaring a I<file> to be in a certain encoding.

If you are using Latin-1 (ISO-8859-1) text, or CP-1252 B<without> Microsoft's
"Smart Quotes" and extended accented letters, you can probably get away with
leaving the string in the default ISO-8859-1 encoding. However, you should 
still get into the habit of converting to UTF-8 (including if the text is
already UTF-8 -- Perl won't know that). Needless to say, anything using a 
non-Latin alphabet will need to be properly converted before Perl (and 
PDF::Builder) can use it. Any developer writing a Perl application to accept 
user input (including from files), and feed it to PDF::Builder, should be aware 
of what encoding the end user is using for their input. Don't assume that any 
file is a given encoding! Ask the user what it is, an be prepared for mistakes 
-- CP-1252 is so widespread that many people think it is identical to Latin-1 
(it isn't).

By the way, it is recommended that you be using I<at least> Perl 5.10 if you
are going to be using any non-ASCII characters. Perl 5.8 may be a little
unpredictable in handling such text.

=head1 LICENSE

This software is Copyright (c) 2017 by Phil M. Perry.

This is free software, licensed under:

  The GNU Lesser General Public License, Version 2.1, February 1999

The GNU Lesser General Public License (LGPL)
Version 2.1, February 1999

  (The master copy of this license lives on the GNU website.)

Copyright (C) 1991, 1999 Free Software Foundation, Inc. 59
51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA

I<Please see the> LICENSE I<file in the distribution root for full details.>

=head1 HISTORY

PDF::API2 was originally written by Alfred Reibenschuh, derived from Martin
Hosken's Text::PDF via the Text::PDF::API wrapper. 
In 2009, Otto Hirr started the PDF::API3 fork, but it never went anywhere.
In 2011, maintenance was taken over by Steve Simms. In 2017, PDF::Builder 
was forked by Phil M. Perry, who desired a more aggressive schedule of new
features and bug fixes than Simms was providing. 

At Simms's request, the name of the new offering was changed from PDF::API4
to PDF::Builder, to reduce the chance of confusion due to parallel development.
Perry's intent is to keep all internal methods as upwardly compatible with
PDF::API2 as possible, although it is likely that there will be some drift
(incompatibilities) over time. At least initially, any program written based on 
PDF::API2 should be convertable to PDF::Builder simply by changing "API2" 
anywhere it occurs to "Builder". See the KNOWN_INCOMP known incompatibilities
file for further information.

=head1 GENERIC METHODS

=over

=item $pdf = PDF::Builder->new(%options)

Creates a new PDF object.  If you will be saving it as a file and
already know the filename, you can give the '-file' option to minimize
possible memory requirements later on. The '-compress' option can be
given to specify stream compression: default is 'flate', 'none' is no
compression.

B<Example:>

    $pdf = PDF::Builder->new();
    ...
    print $pdf->stringify();

    $pdf = PDF::Builder->new(-compress => 'none');
    # equivalent to $pdf->{'forcecompress'} = 'none'; (or older, 0)

    $pdf = PDF::Builder->new();
    ...
    $pdf->saveas('our/new.pdf');

    $pdf = PDF::Builder->new(-file => 'our/new.pdf');
    ...
    $pdf->save();

=cut

sub new {
    my ($class, %options) = @_;

    my $self = {};
    bless $self, $class;
    $self->{'pdf'} = PDF::Builder::Basic::PDF::File->new();

    $self->{'pdf'}->{' version'} = 4;
    $self->{'pages'} = PDF::Builder::Basic::PDF::Pages->new($self->{'pdf'});
    $self->{'pages'}->proc_set(qw(PDF Text ImageB ImageC ImageI));
    $self->{'pages'}->{'Resources'} ||= PDFDict();
    $self->{'pdf'}->new_obj($self->{'pages'}->{'Resources'}) unless $self->{'pages'}->{'Resources'}->is_obj($self->{'pdf'});
    $self->{'catalog'} = $self->{'pdf'}->{'Root'};
    weaken $self->{'catalog'};
    $self->{'fonts'} = {};
    $self->{'pagestack'} = [];
    if (exists $options{'-compress'}) {
      $self->{'forcecompress'} = $options{'-compress'};
      # at this point, no validation of given value! none/flate (0/1).
      # note that >0 is often used as equivalent to 'flate'
    } else {
      $self->{'forcecompress'} = 'flate';
      # code should also allow integers 0 (= 'none') and >0 (= 'flate') 
      # for compatibility with old usage where forcecompress is directly set. 
    }
    $self->preferences(%options);
    if ($options{'-file'}) {
        $self->{' filed'} = $options{'-file'};
        $self->{'pdf'}->create_file($options{'-file'});
    }
    $self->{'infoMeta'} = [qw(Author CreationDate ModDate Creator Producer Title Subject Keywords)];

    my $version = eval { $PDF::Builder::VERSION } || '(Unreleased Version)';
   #$self->info('Producer' => "PDF::Builder $version [$^O]");
    $self->info('Producer' => "PDF::Builder $version [see https://github.com/PhilterPaper/Perl-PDF-Builder/blob/master/SUPPORT]");

    return $self;
} # end of new()

=item $pdf = PDF::Builder->open($pdf_file, %options)

=item $pdf = PDF::Builder->open($pdf_file)

Opens an existing PDF file. See C<new()> for options.

B<Example:>

    $pdf = PDF::Builder->open('our/old.pdf');
    ...
    $pdf->saveas('our/new.pdf');

    $pdf = PDF::Builder->open('our/to/be/updated.pdf');
    ...
    $pdf->update();

=cut

sub open {
    my ($class, $file, %options) = @_;
    croak "File '$file' does not exist" unless -f $file;
    croak "File '$file' is not readable" unless -r $file;

    my $content;
    my $scalar_fh = FileHandle->new();
    CORE::open($scalar_fh, '+<', \$content) or die "Can't begin scalar IO";
    binmode $scalar_fh, ':raw';

    my $disk_fh = FileHandle->new();
    CORE::open($disk_fh, '<', $file) or die "Can't open $file for reading: $!";
    binmode $disk_fh, ':raw';
    $disk_fh->seek(0, 0);
    my $data;
    while (not $disk_fh->eof()) {
        $disk_fh->read($data, 512);
        $scalar_fh->print($data);
    }
    $disk_fh->close();
    $scalar_fh->seek(0, 0);

    my $self = $class->open_scalar($content, %options);
    $self->{'pdf'}->{' fname'} = $file;

    return $self;
} # end of open()

=item $pdf = PDF::Builder->open_scalar($pdf_string, %options)

=item $pdf = PDF::Builder->open_scalar($pdf_string)

Opens a PDF contained in a string. See C<new()> for options.

B<Example:>

    # Read a PDF into a string, for the purpose of demonstration
    open $fh, 'our/old.pdf' or die $@;
    undef $/;  # Read the whole file at once
    $pdf_string = <$fh>;

    $pdf = PDF::Builder->open_scalar($pdf_string);
    ...
    $pdf->saveas('our/new.pdf');

B<Note:> Old name C<openScalar> is B<deprecated!> Convert your code to
use C<open_scalar> instead.

=cut

# Deprecated (renamed)
sub openScalar { 
    warn "Use open_scalar instead of openScalar";
    return open_scalar(@_); 
} ## no critic

sub open_scalar {
    my ($class, $content, %options) = @_;

    my $self = {};
    bless $self, $class;
    foreach my $parameter (keys %options) {
        $self->default($parameter, $options{$parameter});
    }

    $self->{'content_ref'} = \$content;
    my $fh;
    CORE::open($fh, '+<', \$content) or die "Can't begin scalar IO";

    $self->{'pdf'} = PDF::Builder::Basic::PDF::File->open($fh, 1);
    $self->{'pdf'}->{'Root'}->realise();
    $self->{'pages'} = $self->{'pdf'}->{'Root'}->{'Pages'}->realise();
    weaken $self->{'pages'};
    $self->{'pdf'}->{' version'} ||= 3;
    my @pages = proc_pages($self->{'pdf'}, $self->{'pages'});
    $self->{'pagestack'} = [sort { $a->{' pnum'} <=> $b->{' pnum'} } @pages];
    weaken $self->{'pagestack'}->[$_] for (0 .. scalar @{$self->{'pagestack'}});
    $self->{'catalog'} = $self->{'pdf'}->{'Root'};
    weaken $self->{'catalog'};
    $self->{'reopened'} = 1;
    if (exists $options{'-compress'}) {
      $self->{'forcecompress'} = $options{'-compress'};
      # at this point, no validation of given value! none/flate (0/1).
      # note that >0 is often used as equivalent to 'flate'
    } else {
      $self->{'forcecompress'} = 'flate';
      # code should also allow integers 0 (= 'none') and >0 (= 'flate') 
      # for compatibility with old usage where forcecompress is directly set. 
    }
    $self->{'fonts'} = {};
    $self->{'infoMeta'} = [qw(Author CreationDate ModDate Creator Producer Title Subject Keywords)];

    return $self;
} # end of open_scalar()

=item $pdf->preferences(%options)

Controls viewing preferences for the PDF.

B<Page Mode Options:>

=over

=item -fullscreen

Full-screen mode, with no menu bar, window controls, or any other window visible.

=item -thumbs

Thumbnail images visible.

=item -outlines

Document outline visible.

=back

B<Page Layout Options:>

=over

=item -singlepage

Display one page at a time.

=item -onecolumn

Display the pages in one column.

=item -twocolumnleft

Display the pages in two columns, with oddnumbered pages on the left.

=item -twocolumnright

Display the pages in two columns, with oddnumbered pages on the right.

=back

B<Viewer Options:>

=over

=item -hidetoolbar

Specifying whether to hide tool bars.

=item -hidemenubar

Specifying whether to hide menu bars.

=item -hidewindowui

Specifying whether to hide user interface elements.

=item -fitwindow

Specifying whether to resize the document's window to the size of the displayed page.

=item -centerwindow

Specifying whether to position the document's window in the center of the screen.

=item -displaytitle

Specifying whether the window's title bar should display the
document title taken from the Title entry of the document information
dictionary.

=item -afterfullscreenthumbs

Thumbnail images visible after Full-screen mode.

=item -afterfullscreenoutlines

Document outline visible after Full-screen mode.

=item -printscalingnone

Set the default print setting for page scaling to none.

=item -simplex

Print single-sided by default.

=item -duplexflipshortedge

Print duplex by default and flip on the short edge of the sheet.

=item -duplexfliplongedge

Print duplex by default and flip on the long edge of the sheet.

=back

B<Initial Page Options>:

=over

=item -firstpage => [ $page, %options ]

Specifying the page (either a page number or a page object) to be
displayed, plus one of the following options:

=over

=item -fit => 1

Display the page designated by page, with its contents magnified just
enough to fit the entire page within the window both horizontally and
vertically. If the required horizontal and vertical magnification
factors are different, use the smaller of the two, centering the page
within the window in the other dimension.

=item -fith => $top

Display the page designated by page, with the vertical coordinate top
positioned at the top edge of the window and the contents of the page
magnified just enough to fit the entire width of the page within the
window.

=item -fitv => $left

Display the page designated by page, with the horizontal coordinate
left positioned at the left edge of the window and the contents of the
page magnified just enough to fit the entire height of the page within
the window.

=item -fitr => [ $left, $bottom, $right, $top ]

Display the page designated by page, with its contents magnified just
enough to fit the rectangle specified by the coordinates left, bottom,
right, and top entirely within the window both horizontally and
vertically. If the required horizontal and vertical magnification
factors are different, use the smaller of the two, centering the
rectangle within the window in the other dimension.

=item -fitb => 1

Display the page designated by page, with its contents magnified just
enough to fit its bounding box entirely within the window both
horizontally and vertically. If the required horizontal and vertical
magnification factors are different, use the smaller of the two,
centering the bounding box within the window in the other dimension.

=item -fitbh => $top

Display the page designated by page, with the vertical coordinate top
positioned at the top edge of the window and the contents of the page
magnified just enough to fit the entire width of its bounding box
within the window.

=item -fitbv => $left

Display the page designated by page, with the horizontal coordinate
left positioned at the left edge of the window and the contents of the
page magnified just enough to fit the entire height of its bounding
box within the window.

=item -xyz => [ $left, $top, $zoom ]

Display the page designated by page, with the coordinates (left, top)
positioned at the top-left corner of the window and the contents of
the page magnified by the factor zoom. A zero (0) value for any of the
parameters left, top, or zoom specifies that the current value of that
parameter is to be retained unchanged.

=back

=back

B<Example:>

    $pdf->preferences(
        -fullscreen => 1,
        -onecolumn => 1,
        -afterfullscreenoutlines => 1,
        -firstpage => [$page, -fit => 1],
    );

=cut

sub preferences {
    my ($self, %options) = @_;

    # Page Mode Options
    if ($options{'-fullscreen'}) {
        $self->{'catalog'}->{'PageMode'} = PDFName('FullScreen');
    }
    elsif ($options{'-thumbs'}) {
        $self->{'catalog'}->{'PageMode'} = PDFName('UseThumbs');
    }
    elsif ($options{'-outlines'}) {
        $self->{'catalog'}->{'PageMode'} = PDFName('UseOutlines');
    }
    else {
        $self->{'catalog'}->{'PageMode'} = PDFName('UseNone');
    }

    # Page Layout Options
    if ($options{'-singlepage'}) {
        $self->{'catalog'}->{'PageLayout'} = PDFName('SinglePage');
    }
    elsif ($options{'-onecolumn'}) {
        $self->{'catalog'}->{'PageLayout'} = PDFName('OneColumn');
    }
    elsif ($options{'-twocolumnleft'}) {
        $self->{'catalog'}->{'PageLayout'} = PDFName('TwoColumnLeft');
    }
    elsif ($options{'-twocolumnright'}) {
        $self->{'catalog'}->{'PageLayout'} = PDFName('TwoColumnRight');
    }
    else {
        $self->{'catalog'}->{'PageLayout'} = PDFName('SinglePage');
    }

    # Viewer Preferences
    $self->{'catalog'}->{'ViewerPreferences'} ||= PDFDict();
    $self->{'catalog'}->{'ViewerPreferences'}->realise();

    if ($options{'-hidetoolbar'}) {
        $self->{'catalog'}->{'ViewerPreferences'}->{'HideToolbar'} = PDFBool(1);
    }
    if ($options{'-hidemenubar'}) {
        $self->{'catalog'}->{'ViewerPreferences'}->{'HideMenubar'} = PDFBool(1);
    }
    if ($options{'-hidewindowui'}) {
        $self->{'catalog'}->{'ViewerPreferences'}->{'HideWindowUI'} = PDFBool(1);
    }
    if ($options{'-fitwindow'}) {
        $self->{'catalog'}->{'ViewerPreferences'}->{'FitWindow'} = PDFBool(1);
    }
    if ($options{'-centerwindow'}) {
        $self->{'catalog'}->{'ViewerPreferences'}->{'CenterWindow'} = PDFBool(1);
    }
    if ($options{'-displaytitle'}) {
        $self->{'catalog'}->{'ViewerPreferences'}->{'DisplayDocTitle'} = PDFBool(1);
    }
    if ($options{'-righttoleft'}) {
        $self->{'catalog'}->{'ViewerPreferences'}->{'Direction'} = PDFName('R2L');
    }

    if ($options{'-afterfullscreenthumbs'}) {
        $self->{'catalog'}->{'ViewerPreferences'}->{'NonFullScreenPageMode'} = PDFName('UseThumbs');
    }
    elsif ($options{'-afterfullscreenoutlines'}) {
        $self->{'catalog'}->{'ViewerPreferences'}->{'NonFullScreenPageMode'} = PDFName('UseOutlines');
    }
    else {
        $self->{'catalog'}->{'ViewerPreferences'}->{'NonFullScreenPageMode'} = PDFName('UseNone');
    }

    if ($options{'-printscalingnone'}) {
        $self->{'catalog'}->{'ViewerPreferences'}->{'PrintScaling'} = PDFName('None');
    }

    if ($options{'-simplex'}) {
        $self->{'catalog'}->{'ViewerPreferences'}->{'Duplex'} = PDFName('Simplex');
    }
    elsif ($options{'-duplexfliplongedge'}) {
        $self->{'catalog'}->{'ViewerPreferences'}->{'Duplex'} = PDFName('DuplexFlipLongEdge');
    }
    elsif ($options{'-duplexflipshortedge'}) {
        $self->{'catalog'}->{'ViewerPreferences'}->{'Duplex'} = PDFName('DuplexFlipShortEdge');
    }

    # Open Action
    if ($options{'-firstpage'}) {
        my ($page, %args) = @{$options{'-firstpage'}};
        $args{'-fit'} = 1 unless scalar keys %args;

        # $page can be either a page number (which needs to be wrapped
        # in PDFNum) or a page object (which doesn't).
        $page = PDFNum($page) unless ref($page);

        if (defined $args{'-fit'}) {
            $self->{'catalog'}->{'OpenAction'} = PDFArray($page, PDFName('Fit'));
        }
        elsif (defined $args{'-fith'}) {
            $self->{'catalog'}->{'OpenAction'} = PDFArray($page, PDFName('FitH'), PDFNum($args{'-fith'}));
        }
        elsif (defined $args{'-fitb'}) {
            $self->{'catalog'}->{'OpenAction'} = PDFArray($page, PDFName('FitB'));
        }
        elsif (defined $args{'-fitbh'}) {
            $self->{'catalog'}->{'OpenAction'} = PDFArray($page, PDFName('FitBH'), PDFNum($args{'-fitbh'}));
        }
        elsif (defined $args{'-fitv'}) {
            $self->{'catalog'}->{'OpenAction'} = PDFArray($page, PDFName('FitV'), PDFNum($args{'-fitv'}));
        }
        elsif (defined $args{'-fitbv'}) {
            $self->{'catalog'}->{'OpenAction'} = PDFArray($page, PDFName('FitBV'), PDFNum($args{'-fitbv'}));
        }
        elsif (defined $args{'-fitr'}) {
            croak 'insufficient parameters to -fitr => []' unless scalar @{$args{'-fitr'}} == 4;
            $self->{'catalog'}->{'OpenAction'} = PDFArray($page, PDFName('FitR'), map { PDFNum($_) } @{$args{'-fitr'}});
        }
        elsif (defined $args{'-xyz'}) {
            croak 'insufficient parameters to -xyz => []' unless scalar @{$args{'-xyz'}} == 3;
            $self->{'catalog'}->{'OpenAction'} = PDFArray($page, PDFName('XYZ'), map { PDFNum($_) } @{$args{'-xyz'}});
        }
    }
    $self->{'pdf'}->out_obj($self->{'catalog'});

    return $self;
}  # end of preferences()

=item $val = $pdf->default($parameter)

=item $pdf->default($parameter, $value)

Gets/sets the default value for a behavior of PDF::Builder.

B<Supported Parameters:>

=over

=item nounrotate

prohibits Builder from rotating imported/opened page to re-create a
default pdf-context.

=item pageencaps

enables that Builder will add save/restore commands upon importing/opening
pages to preserve graphics-state for modification.

=item copyannots

enables importing of annotations (B<*EXPERIMENTAL*>).

=back

=cut

sub default {
    my ($self, $parameter, $value) = @_;

    # Parameter names may consist of lowercase letters, numbers, and underscores
    $parameter = lc $parameter;
    $parameter =~ s/[^a-z\d_]//g;

    my $previous_value = $self->{$parameter};
    if (defined $value) {
        $self->{$parameter} = $value;
    }

    return $previous_value;
}

=item $version = $pdf->version($new_version)

=item $version = $pdf->version()

Get/set the PDF version (e.g. 1.4)

=cut

sub version {
    my $self = shift();
    if (scalar @_) {
        my $version = shift();
        croak "Invalid version $version" unless $version =~ /^(?:1\.)?([0-9]+)$/;
        $self->{'pdf'}->{' version'} = $1;
    }

    return '1.' . $self->{'pdf'}->{' version'};
}

=item $bool = $pdf->isEncrypted()

Checks if the previously opened PDF is encrypted.

=cut

sub isEncrypted {
    my $self = shift;

    return defined($self->{'pdf'}->{'Encrypt'}) ? 1 : 0;
}

=item %infohash = $pdf->info(%infohash)

Gets/sets the info structure of the document.

B<Example:>

    %h = $pdf->info(
        'Author'       => "Alfred Reibenschuh",
        'CreationDate' => "D:20020911000000+01'00'",
        'ModDate'      => "D:YYYYMMDDhhmmssOHH'mm'",
        'Creator'      => "fredos-script.pl",
        'Producer'     => "PDF::Builder",
        'Title'        => "some Publication",
        'Subject'      => "perl ?",
        'Keywords'     => "all good things are pdf"
    );
    print "Author: $h{'Author'}\n";

=cut

sub info {
    my ($self, %opt) = @_;

    if(not defined($self->{'pdf'}->{'Info'})) {
       $self->{'pdf'}->{'Info'} = PDFDict();
       $self->{'pdf'}->new_obj($self->{'pdf'}->{'Info'});
    } else {
       $self->{'pdf'}->{'Info'}->realise();
    }

    # Maintenance Note: Since we're not shifting at the beginning of
    # this sub, this "if" will always be true
    if (scalar @_) {
        foreach my $k (@{$self->{'infoMeta'}}) {
            next unless defined $opt{$k};
            if (is_utf8($opt{$k})) {
                $self->{'pdf'}->{'Info'}->{$k} = PDFUtf($opt{$k} || 'NONE');
	   #} elsif (is_utf8($opt{$k}) || utf8::valid($opt{$k})) {
           #    $self->{'pdf'}->{'Info'}->{$k} = PDFUtf($opt{$k} || 'NONE');
            } else {
                $self->{'pdf'}->{'Info'}->{$k} = PDFStr($opt{$k} || 'NONE');
            }
        }
        $self->{'pdf'}->out_obj($self->{'pdf'}->{'Info'});
    }
    
    if (defined $self->{'pdf'}->{'Info'}) {
        %opt = ();
        foreach my $k (@{$self->{'infoMeta'}}) {
            next unless defined $self->{'pdf'}->{'Info'}->{$k};
            $opt{$k} = $self->{'pdf'}->{'Info'}->{$k}->val();
            if ((unpack('n', $opt{$k}) == 0xfffe) or (unpack('n', $opt{$k}) == 0xfeff)) {
                $opt{$k} = decode('UTF-16', $self->{'pdf'}->{'Info'}->{$k}->val());
            }
        }
    }

    return %opt;
} # end of info()

=item @metadata_attributes = $pdf->infoMetaAttributes(@metadata_attributes)

Gets/sets the supported info-structure tags.

B<Example:>

    @attributes = $pdf->infoMetaAttributes;
    print "Supported Attributes: @attr\n";

    @attributes = $pdf->infoMetaAttributes('CustomField1');
    print "Supported Attributes: @attributes\n";

=cut

sub infoMetaAttributes {
    my ($self, @attr) = @_;

    if (scalar @attr) {
        my %at = map { $_ => 1 } @{$self->{'infoMeta'}}, @attr;
        @{$self->{'infoMeta'}} = keys %at;
    }

    return @{$self->{'infoMeta'}};
}

=item $xml = $pdf->xmpMetadata($xml)

Gets/sets the XMP XML data stream.

B<Example:>

    $xml = $pdf->xmpMetadata();
    print "PDFs Metadata reads: $xml\n";
    $xml=<<EOT;
    <?xpacket begin='' id='W5M0MpCehiHzreSzNTczkc9d'?>
    <?adobe-xap-filters esc="CRLF"?>
    <x:xmpmeta
      xmlns:x='adobe:ns:meta/'
      x:xmptk='XMP toolkit 2.9.1-14, framework 1.6'>
        <rdf:RDF
          xmlns:rdf='http://www.w3.org/1999/02/22-rdf-syntax-ns#'
          xmlns:iX='http://ns.adobe.com/iX/1.0/'>
            <rdf:Description
              rdf:about='uuid:b8659d3a-369e-11d9-b951-000393c97fd8'
              xmlns:pdf='http://ns.adobe.com/pdf/1.3/'
              pdf:Producer='Acrobat Distiller 6.0.1 for Macintosh'></rdf:Description>
            <rdf:Description
              rdf:about='uuid:b8659d3a-369e-11d9-b951-000393c97fd8'
              xmlns:xap='http://ns.adobe.com/xap/1.0/'
              xap:CreateDate='2004-11-14T08:41:16Z'
              xap:ModifyDate='2004-11-14T16:38:50-08:00'
              xap:CreatorTool='FrameMaker 7.0'
              xap:MetadataDate='2004-11-14T16:38:50-08:00'></rdf:Description>
            <rdf:Description
              rdf:about='uuid:b8659d3a-369e-11d9-b951-000393c97fd8'
              xmlns:xapMM='http://ns.adobe.com/xap/1.0/mm/'
              xapMM:DocumentID='uuid:919b9378-369c-11d9-a2b5-000393c97fd8'/></rdf:Description>
            <rdf:Description
              rdf:about='uuid:b8659d3a-369e-11d9-b951-000393c97fd8'
              xmlns:dc='http://purl.org/dc/elements/1.1/'
              dc:format='application/pdf'>
                <dc:description>
                  <rdf:Alt>
                    <rdf:li xml:lang='x-default'>Adobe Portable Document Format (PDF)</rdf:li>
                  </rdf:Alt>
                </dc:description>
                <dc:creator>
                  <rdf:Seq>
                    <rdf:li>Adobe Systems Incorporated</rdf:li>
                  </rdf:Seq>
                </dc:creator>
                <dc:title>
                  <rdf:Alt>
                    <rdf:li xml:lang='x-default'>PDF Reference, version 1.6</rdf:li>
                  </rdf:Alt>
                </dc:title>
            </rdf:Description>
        </rdf:RDF>
    </x:xmpmeta>
    <?xpacket end='w'?>
    EOT

    $xml = $pdf->xmpMetadata($xml);
    print "PDF metadata now reads: $xml\n";

=cut

sub xmpMetadata {
    my ($self, $value) = @_;

    if(not defined($self->{'catalog'}->{'Metadata'})) {
            $self->{'catalog'}->{'Metadata'} = PDFDict();
            $self->{'catalog'}->{'Metadata'}->{'Type'} = PDFName('Metadata');
            $self->{'catalog'}->{'Metadata'}->{'Subtype'} = PDFName('XML');
            $self->{'pdf'}->new_obj($self->{'catalog'}->{'Metadata'});
    } else {
        $self->{'catalog'}->{'Metadata'}->realise();
        $self->{'catalog'}->{'Metadata'}->{' stream'} = unfilter($self->{'catalog'}->{'Metadata'}->{'Filter'}, $self->{'catalog'}->{'Metadata'}->{' stream'});
        delete $self->{'catalog'}->{'Metadata'}->{' nofilt'};
        delete $self->{'catalog'}->{'Metadata'}->{'Filter'};
    }

    my $md=$self->{'catalog'}->{'Metadata'};

    if (defined $value) {
        $md->{' stream'} = $value;
        delete $md->{'Filter'};
        delete $md->{' nofilt'};
        $self->{'pdf'}->out_obj($md);
        $self->{'pdf'}->out_obj($self->{'catalog'});
    }

    return $md->{' stream'};
} # end of xmpMetadata()

=item $pdf->pageLabel($index, $options)

Sets page label options.

B<Supported Options:>

=over

=item -style

Roman, roman, decimal, Alpha or alpha.

=item -start

Restart numbering at given number.

=item -prefix

Text prefix for numbering.

=back

B<Example:>

    # Start with Roman Numerals
    $pdf->pageLabel(0, {
        -style => 'roman',
    });

    # Switch to Arabic
    $pdf->pageLabel(4, {
        -style => 'decimal',
    });

    # Numbering for Appendix A
    $pdf->pageLabel(32, {
        -start => 1,
        -prefix => 'A-'
    });

    # Numbering for Appendix B
    $pdf->pageLabel( 36, {
        -start => 1,
        -prefix => 'B-'
    });

    # Numbering for the Index
    $pdf->pageLabel(40, {
        -style => 'Roman'
        -start => 1,
        -prefix => 'Index '
    });

=cut

sub pageLabel {
    my $self = shift();

    $self->{'catalog'}->{'PageLabels'} ||= PDFDict();
    $self->{'catalog'}->{'PageLabels'}->{'Nums'} ||= PDFArray();

    my $nums = $self->{'catalog'}->{'PageLabels'}->{'Nums'};
    while (scalar @_) {
        my $index = shift();
        my $opts = shift();

        $nums->add_elements(PDFNum($index));

        my $d = PDFDict();
        $d->{'S'} = PDFName($opts->{'-style'} eq 'Roman' ? 'R' :
                            $opts->{'-style'} eq 'roman' ? 'r' :
                            $opts->{'-style'} eq 'Alpha' ? 'A' :
                            $opts->{'-style'} eq 'alpha' ? 'a' : 'D');

        if (defined $opts->{'-prefix'}) {
            $d->{'P'} = PDFStr($opts->{'-prefix'});
        }

        if (defined $opts->{'-start'}) {
            $d->{'St'} = PDFNum($opts->{'-start'});
        }

        $nums->add_elements($d);
    }
} # end of pageLabel()

=item $pdf->finishobjects(@objects)

Force objects to be written to file if possible.

B<Example:>

    $pdf = PDF::Builder->new(-file => 'our/new.pdf');
    ...
    $pdf->finishobjects($page, $gfx, $txt);
    ...
    $pdf->save();

=cut

sub finishobjects {
    my ($self, @objs) = @_;

    if ($self->{'reopened'}) {
        die "invalid method invocation: no file, use 'saveas' instead.";
    } elsif ($self->{' filed'}) {
        $self->{'pdf'}->ship_out(@objs);
    } else {
        die "invalid method invocation: no file, use 'saveas' instead.";
    }
}

sub proc_pages {
    my ($pdf, $object) = @_;

    if (defined $object->{'Resources'}) {
        eval {
            $object->{'Resources'}->realise();
        };
    }

    my @pages;
    $pdf->{' apipagecount'} ||= 0;
    foreach my $page ($object->{'Kids'}->elementsof()) {
        $page->realise();
        if ($page->{'Type'}->val() eq 'Pages') {
            push @pages, proc_pages($pdf, $page);
        }
        else {
            $pdf->{' apipagecount'}++;
            $page->{' pnum'} = $pdf->{' apipagecount'};
            if (defined $page->{'Resources'}) {
                eval {
                    $page->{'Resources'}->realise();
                };
            }
            push @pages, $page;
        }
    }

    return @pages;
} # end of proc_pages()

=item $pdf->update()

Saves a previously opened document.

B<Example:>

    $pdf = PDF::Builder->open('our/to/be/updated.pdf');
    ...
    $pdf->update();

=cut

sub update {
    my $self = shift;

    $self->saveas($self->{'pdf'}->{' fname'});
}

=item $pdf->saveas($file)

Save the document to $file and remove the object structure from memory.

B<Example:>

    $pdf = PDF::Builder->new();
    ...
    $pdf->saveas('our/new.pdf');

=cut

sub saveas {
    my ($self, $file) = @_;

    if ($self->{'reopened'}) {
        $self->{'pdf'}->append_file();
	my $fh;
        CORE::open($fh, '>', $file) or die "Can't open $file for writing: $!";
        binmode($fh, ':raw');
        print $fh ${$self->{'content_ref'}};
        CORE::close($fh);
    } elsif ($self->{' filed'}) {
        $self->{'pdf'}->close_file();
    } else {
        $self->{'pdf'}->out_file($file);
    }

    $self->end();
}

sub save {
    my ($self, $file) = @_;

    if ($self->{'reopened'}) {
        die "invalid method invocation: use 'saveas' instead.";
    } elsif ($self->{' filed'}) {
        $self->{'pdf'}->close_file();
    } else {
        die "invalid method invocation: use 'saveas' instead.";
    }

    $self->end();
}

=item $string = $pdf->stringify()

Return the document as a string and remove the object structure from memory.

B<Example:>

    $pdf = PDF::Builder->new();
    ...
    print $pdf->stringify();

=cut

# Maintainer's note: The object is being destroyed because it contains
# circular references that would otherwise result in memory not being
# freed if the object merely goes out of scope.  If possible, the
# circular references should be eliminated so that stringify doesn't
# need to be destructive.
#
# I've opted not to just require a separate call to release() because
# it would likely introduce memory leaks in many existing programs
# that use this module.
# - Steve S. (see bug RT 81530)

sub stringify {
    my $self = shift;

    my $str;
    if ((defined $self->{'reopened'}) and ($self->{'reopened'} == 1)) {
        $self->{'pdf'}->append_file();
        $str = ${$self->{'content_ref'}};
    } else {
        my $fh = FileHandle->new();
        CORE::open($fh, '>', \$str) || die "Can't begin scalar IO";
        $self->{'pdf'}->out_file($fh);
        $fh->close();
    }
    $self->end();

    return $str;
}

sub release {
    my $self = shift;
    $self->end();

    return;
}

=item $pdf->end()

Remove the object structure from memory.  PDF::Builder contains circular
references, so this call is necessary in long-running processes to
keep from running out of memory.

This will be called automatically when you save or stringify a PDF.
You should only need to call it explicitly if you are reading PDF
files and not writing them.

=cut

sub end {
    my $self = shift;
    $self->{'pdf'}->release() if defined $self->{'pdf'};

    foreach my $key (keys %$self) {
        $self->{$key} = undef;
        delete $self->{$key};
    }

    return;
}

=back

=head1 PAGE METHODS

=over

=item $page = $pdf->page()

=item $page = $pdf->page($page_number)

Returns a new page object.  By default, the page is added to the end
of the document.  If you include an existing page number, the new page
will be inserted in that position, pushing existing pages back.

If $page_number is -1, the new page is inserted as the second-last page;
if $page_number is 0, the new page is inserted as the last page.

B<Example:>

    $pdf = PDF::Builder->new();

    # Add a page.  This becomes page 1.
    $page = $pdf->page();

    # Add a new first page.  $page becomes page 2.
    $another_page = $pdf->page(1);

=cut

sub page {
    my $self = shift;
    my $index = shift() || 0;  # default to new "last" page
    my $page;

    if ($index == 0) {
        $page = PDF::Builder::Page->new($self->{'pdf'}, $self->{'pages'});
    } else {
        $page = PDF::Builder::Page->new($self->{'pdf'}, $self->{'pages'}, $index-1);
    }
    $page->{' apipdf'} = $self->{'pdf'};
    $page->{' api'} = $self;
    weaken $page->{' apipdf'};
    weaken $page->{' api'};
    $self->{'pdf'}->out_obj($page);
    $self->{'pdf'}->out_obj($self->{'pages'});
    if ($index == 0) {
        push @{$self->{'pagestack'}}, $page;
	weaken $self->{'pagestack'}->[-1];
    } elsif ($index < 0) {
        splice @{$self->{'pagestack'}}, $index, 0, $page;
	weaken $self->{'pagestack'}->[$index];
    } else {
        splice @{$self->{'pagestack'}}, $index-1, 0, $page;
	weaken $self->{'pagestack'}->[$index - 1];
    }

 #   $page->{'Resources'}=$self->{'pages'}->{'Resources'};
    return $page;
} # end of page()

=item $page = $pdf->openpage($page_number)

Returns the L<PDF::Builder::Page> object of page $page_number.

If $page_number is 0 or -1, it will return the last page in the
document.

B<Example:>

    $pdf = PDF::Builder->open('our/99page.pdf');
    $page = $pdf->openpage(1);   # returns the first page
    $page = $pdf->openpage(99);  # returns the last page
    $page = $pdf->openpage(-1);  # returns the last page
    $page = $pdf->openpage(999); # returns undef

=cut

sub openpage {
    my $self = shift();
    my $index = shift() || 0;
    my ($page, $rotate, $media, $trans);

    if ($index == 0) {
        $page = $self->{'pagestack'}->[-1];
    } elsif ($index < 0) {
        $page = $self->{'pagestack'}->[$index];
    } else {
        $page = $self->{'pagestack'}->[$index - 1];
    }
    return unless ref($page);

    if (ref($page) ne 'PDF::Builder::Page') {
        bless $page, 'PDF::Builder::Page';
        $page->{' apipdf'} = $self->{'pdf'};
        $page->{' api'} = $self;
	weaken $page->{' apipdf'};
	weaken $page->{' api'};
        $self->{'pdf'}->out_obj($page);
        if (($rotate = $page->find_prop('Rotate')) and (not defined($page->{' fixed'}) or $page->{' fixed'} < 1)) {
            $rotate = ($rotate->val() + 360) % 360;

            if ($rotate != 0 and not $self->default('nounrotate')) {
                $page->{'Rotate'} = PDFNum(0);
                foreach my $mediatype (qw(MediaBox CropBox BleedBox TrimBox ArtBox)) {
                    if ($media = $page->find_prop($mediatype)) {
                        $media = [ map { $_->val() } $media->elementsof() ];
                    } else {
                        $media = [0, 0, 612, 792]; # US Letter default
                        next if $mediatype ne 'MediaBox';
                    }
                    if ($rotate == 90) {
                        $trans = "0 -1 1 0 0 $media->[2] cm" if $mediatype eq 'MediaBox';
                        $media = [$media->[1], $media->[0], $media->[3], $media->[2]];
                    } elsif ($rotate == 180) {
                        $trans = "-1 0 0 -1 $media->[2] $media->[3] cm" if $mediatype eq 'MediaBox';
                    } elsif ($rotate == 270) {
                        $trans = "0 1 -1 0 $media->[3] 0 cm" if $mediatype eq 'MediaBox';
                        $media = [$media->[1], $media->[0], $media->[3], $media->[2]];
                    }
                    $page->{$mediatype} = PDFArray(map { PDFNum($_) } @$media);
                }
            } else {
                $trans = '';
            }
        } else {
            $trans = '';
        }

        if (defined $page->{'Contents'} and (not defined($page->{' fixed'}) or $page->{' fixed'} < 1)) {
            $page->fixcontents();
            my $uncontent = delete $page->{'Contents'};
            my $content = $page->gfx();
            $content->add(" $trans ");

            if ($self->default('pageencaps')) {
                $content->{' stream'} .= ' q ';
            }
            foreach my $k ($uncontent->elementsof()) {
                $k->realise();
                $content->{' stream'} .= ' ' . unfilter($k->{'Filter'}, $k->{' stream'}) . ' ';
            }
            if ($self->default('pageencaps')) {
                $content->{' stream'} .= ' Q ';
            }

            ## $content->{'Length'} = PDFNum(length($content->{' stream'}));
            # this will be fixed by the following code or content or filters

            ## if we like compress we will do it now to do quicker saves
            if ($self->{'forcecompress'} eq 'flate' || 
		$self->{'forcecompress'} =~ m/^[1-9]\d*$/) {
                # $content->compressFlate();
                $content->{' stream'} = dofilter($content->{'Filter'}, $content->{' stream'});
                $content->{' nofilt'} = 1;
                delete $content->{'-docompress'};
                $content->{'Length'} = PDFNum(length($content->{' stream'}));
            }
        }
        $page->{' fixed'} = 1;
    }

    $self->{'pdf'}->out_obj($page);
    $self->{'pdf'}->out_obj($self->{'pages'});
    $page->{' apipdf'} = $self->{'pdf'};
    $page->{' api'} = $self;
    weaken $page->{' apipdf'};
    weaken $page->{' api'};
    $page->{' reopened'} = 1;

    return $page;
} # end of openpage()


sub walk_obj {
    my ($object_cache, $source_pdf, $target_pdf, $source_object, @keys) = @_;

    if (ref($source_object) =~ /Objind$/) {
        $source_object->realise();
    }

    return $object_cache->{scalar $source_object} if defined $object_cache->{scalar $source_object};
   #die "infinite loop while copying objects" if $source_object->{' copied'};

    my $target_object = $source_object->copy($source_pdf); ## thanks to: yaheath // Fri, 17 Sep 2004

   #$source_object->{' copied'} = 1;
    $target_pdf->new_obj($target_object) if $source_object->is_obj($source_pdf);

    $object_cache->{scalar $source_object} = $target_object;

    if (ref($source_object) =~ /Array$/) {
        $target_object->{' val'} = [];
        foreach my $k ($source_object->elementsof()) {
            $k->realise() if ref($k) =~ /Objind$/;
            $target_object->add_elements(walk_obj($object_cache, $source_pdf, $target_pdf, $k));
        }
    } elsif (ref($source_object) =~ /Dict$/) {
        @keys = keys(%$target_object) unless scalar @keys;
        foreach my $k (@keys) {
            next if $k =~ /^ /;
            next unless defined $source_object->{$k};
            $target_object->{$k} = walk_obj($object_cache, $source_pdf, $target_pdf, $source_object->{$k});
        }
        if ($source_object->{' stream'}) {
            if ($target_object->{'Filter'}) {
                $target_object->{' nofilt'} = 1;
            } else {
                delete $target_object->{' nofilt'};
                $target_object->{'Filter'} = PDFArray(PDFName('FlateDecode'));
            }
            $target_object->{' stream'} = $source_object->{' stream'};
        }
    }
    delete $target_object->{' streamloc'};
    delete $target_object->{' streamsrc'};

    return $target_object;
} # end of walk_obj()

=item $xoform = $pdf->importPageIntoForm($source_pdf, $source_page_number)

Returns a Form XObject created by extracting the specified page from $source_pdf.

This is useful if you want to transpose the imported page somewhat
differently onto a page (e.g. two-up, four-up, etc.).

If $source_page_number is 0 or -1, it will return the last page in the
document.

B<Example:>

    $pdf = PDF::Builder->new();
    $old = PDF::Builder->open('our/old.pdf');
    $page = $pdf->page();
    $gfx = $page->gfx();

    # Import Page 2 from the old PDF
    $xo = $pdf->importPageIntoForm($old, 2);

    # Add it to the new PDF's first page at 1/2 scale
    $gfx->formimage($xo, 0, 0, 0.5);

    $pdf->saveas('our/new.pdf');

B<Note:> You can only import a page from an existing PDF file.

=cut

sub importPageIntoForm {
    my ($self, $s_pdf, $s_idx) = @_;
    $s_idx ||= 0;

    unless (ref($s_pdf) and $s_pdf->isa('PDF::Builder')) {
        die "Invalid usage: first argument must be PDF::Builder instance, not: " . ref($s_pdf);
    }

    my ($s_page, $xo);

    $xo = $self->xo_form();

    if (ref($s_idx) eq 'PDF::Builder::Page') {
        $s_page = $s_idx;
    } else {
        $s_page = $s_pdf->openpage($s_idx);
    }

    $self->{'apiimportcache'} ||= {};
    $self->{'apiimportcache'}->{$s_pdf} ||= {};

    # This should never get past MediaBox, since it's a required object.
    foreach my $k (qw(MediaBox ArtBox TrimBox BleedBox CropBox)) {
       #next unless defined $s_page->{$k};
       #my $box = walk_obj($self->{'apiimportcache'}->{$s_pdf}, $s_pdf->{'pdf'}, $self->{'pdf'}, $s_page->{$k});
        next unless defined $s_page->find_prop($k);
        my $box = walk_obj($self->{'apiimportcache'}->{$s_pdf}, $s_pdf->{'pdf'}, $self->{'pdf'}, $s_page->find_prop($k));
        $xo->bbox(map { $_->val() } $box->elementsof());
        last;
    }
    $xo->bbox(0, 0, 612, 792) unless defined $xo->{'BBox'}; # US Letter default

    foreach my $k (qw(Resources)) {
        $s_page->{$k} = $s_page->find_prop($k);
        next unless defined $s_page->{$k};
        $s_page->{$k}->realise() if ref($s_page->{$k}) =~ /Objind$/;

        foreach my $sk (qw(XObject ExtGState Font ProcSet Properties ColorSpace Pattern Shading)) {
            next unless defined $s_page->{$k}->{$sk};
            $s_page->{$k}->{$sk}->realise() if ref($s_page->{$k}->{$sk}) =~ /Objind$/;
            foreach my $ssk (keys %{$s_page->{$k}->{$sk}}) {
                next if $ssk =~ /^ /;
                $xo->resource($sk, $ssk, walk_obj($self->{'apiimportcache'}->{$s_pdf}, $s_pdf->{'pdf'}, $self->{'pdf'}, $s_page->{$k}->{$sk}->{$ssk}));
            }
        }
    }

    # create a whole content stream
    ## technically it is possible to submit an unfinished
    ## (e.g., newly created) source-page, but that's nonsense,
    ## so we expect a page fixed by openpage and die otherwise
    die "page not processed via openpage ..." unless $s_page->{' fixed'} == 1;

    # since the source page comes from openpage it may already
    # contain the required starting 'q' without the final 'Q'
    # if forcecompress is in effect
    if (defined $s_page->{'Contents'}) {
        $s_page->fixcontents();

        $xo->{' stream'} = '';
        # openpage pages only contain one stream
        my ($k) = $s_page->{'Contents'}->elementsof();
        $k->realise();
        if ($k->{' nofilt'}) {
          # we have a finished stream here
          # so we unfilter
          $xo->add('q', unfilter($k->{'Filter'}, $k->{' stream'}), 'Q');
        } else {
          # stream is an unfinished/unfiltered content
          # so we just copy it and add the required "qQ"
            $xo->add('q', $k->{' stream'}, 'Q');
        }
        $xo->compressFlate() if $self->{'forcecompress'} eq 'flate' ||
	                        $self->{'forcecompress'} =~ m/^[1-9]\d*$/;
    }

    return $xo;
} # end of importPageIntoForm()

=item $page = $pdf->import_page($source_pdf, $source_page_number, $target_page_number)

Imports a page from $source_pdf and adds it to the specified position
in $pdf.

If C<$source_page_number> or C<$target_page_number> is 0 (the default) or -1, 
the last page in the document is used.

B<Note:> If you pass a page I<object> instead of a page I<number> for
C<$target_page_number>, the contents of the page will be B<merged> into the
existing page.

B<Example:>

    $pdf = PDF::Builder->new();
    $old = PDF::Builder->open('our/old.pdf');

    # Add page 2 from the old PDF as page 1 of the new PDF
    $page = $pdf->import_page($old, 2);

    $pdf->saveas('our/new.pdf');

B<Note:> You can only import a page from an existing PDF file.

B<Note:> Old name C<importpage> is B<deprecated!> Convert your code to
use C<import_page> instead.

=cut

# Deprecated (renamed)
sub importpage { 
    warn "Use import_page instead of importpage";
    return import_page(@_); 
} ## no critic

sub import_page {
    my ($self, $s_pdf, $s_idx, $t_idx) = @_;

    $s_idx ||= 0;  # default to last page
    $t_idx ||= 0;  # default to last page
    my ($s_page, $t_page);

    unless (ref($s_pdf) and $s_pdf->isa('PDF::Builder')) {
        die "Invalid usage: first argument must be PDF::Builder instance, not: " . ref($s_pdf);
    }

    if (ref($s_idx) eq 'PDF::Builder::Page') {
        $s_page = $s_idx;
    } else {
        $s_page = $s_pdf->openpage($s_idx);
    }

    if (ref($t_idx) eq 'PDF::Builder::Page') {
        $t_page = $t_idx;
    } else {
        if ($self->pages() < $t_idx) {
            $t_page = $self->page();
        } else {
            $t_page = $self->page($t_idx);
        }
    }

    $self->{'apiimportcache'} = $self->{'apiimportcache'} || {};
    $self->{'apiimportcache'}->{$s_pdf} = $self->{'apiimportcache'}->{$s_pdf} || {};

    # we now import into a form to keep
    # all that nasty resources from polluting
    # our very own resource naming space.
    my $xo = $self->importPageIntoForm($s_pdf, $s_page);

    # copy all page dimensions
    foreach my $k (qw(MediaBox ArtBox TrimBox BleedBox CropBox)) {
        my $prop = $s_page->find_prop($k);
        next unless defined $prop;

        my $box = walk_obj({}, $s_pdf->{'pdf'}, $self->{'pdf'}, $prop);
        my $method = lc $k;

        $t_page->$method(map { $_->val() } $box->elementsof());
    }

    $t_page->gfx()->formimage($xo, 0, 0, 1);

    # copy annotations and/or form elements as well
    if (exists $s_page->{'Annots'} and $s_page->{'Annots'} and $self->{'copyannots'}) {
        # first set up the AcroForm, if required
        my $AcroForm;
        if (my $a = $s_pdf->{'pdf'}->{'Root'}->realise()->{'AcroForm'}) {
            $a->realise();

            $AcroForm = walk_obj({}, $s_pdf->{'pdf'}, $self->{'pdf'}, $a, qw(NeedAppearances SigFlags CO DR DA Q));
        }
        my @Fields = ();
        my @Annots = ();
        foreach my $a ($s_page->{'Annots'}->elementsof()) {
            $a->realise();
            my $t_a = PDFDict();
            $self->{'pdf'}->new_obj($t_a);
            # these objects are likely to be both annotations and Acroform fields
            # key names are copied from PDF Reference 1.4 (Tables)
            my @k = (
                qw( Type Subtype Contents P Rect NM M F BS Border AP AS C CA T Popup A AA StructParent Rotate
                ),                                    # Annotations - Common (8.10)
                qw(Subtype Contents Open Name),       # Text Annotations (8.15)
                qw(Subtype Contents Dest H PA),       # Link Annotations (8.16)
                qw(Subtype Contents DA Q),            # Free Text Annotations (8.17)
                qw(Subtype Contents L BS LE IC),      # Line Annotations (8.18)
                qw(Subtype Contents BS IC),           # Square and Circle Annotations (8.20)
                qw(Subtype Contents QuadPoints),      # Markup Annotations (8.21)
                qw(Subtype Contents Name),            # Rubber Stamp Annotations (8.22)
                qw(Subtype Contents InkList BS),      # Ink Annotations (8.23)
                qw(Subtype Contents Parent Open),     # Popup Annotations (8.24)
                qw(Subtype FS Contents Name),         # File Attachment Annotations (8.25)
                qw(Subtype Sound Contents Name),      # Sound Annotations (8.26)
                qw(Subtype Movie Contents A),         # Movie Annotations (8.27)
                qw(Subtype Contents H MK),            # Widget Annotations (8.28)
                                                      # Printers Mark Annotations (none)
                                                      # Trap Network Annotations (none)
            );
            push @k, (
                qw( Subtype FT Parent Kids T TU TM Ff V DV AA
                ),                                    # Fields - Common (8.49)
                qw(DR DA Q),                          # Fields containing variable text (8.51)
                qw(Opt),                              # Checkbox field (8.54)
                qw(Opt),                              # Radio field (8.55)
                qw(MaxLen),                           # Text field (8.57)
                qw(Opt TI I),                         # Choice field (8.59)
            ) if $AcroForm;

            # sorting out dupes
            my %ky = map { $_ => 1 } @k;
            # we do P separately, as it points to the page the Annotation is on
            delete $ky{'P'};
            # copy everything else
            foreach my $k (keys %ky) {
                next unless defined $a->{$k};
                $a->{$k}->realise();
                $t_a->{$k} = walk_obj({}, $s_pdf->{'pdf'}, $self->{'pdf'}, $a->{$k});
            }
            $t_a->{'P'} = $t_page;
            push @Annots, $t_a;
            push @Fields, $t_a if ($AcroForm and $t_a->{'Subtype'}->val() eq 'Widget');
        }
        $t_page->{'Annots'} = PDFArray(@Annots);
        $AcroForm->{'Fields'} = PDFArray(@Fields) if $AcroForm;
        $self->{'pdf'}->{'Root'}->{'AcroForm'} = $AcroForm;
    }
    $t_page->{' imported'} = 1;

    $self->{'pdf'}->out_obj($t_page);
    $self->{'pdf'}->out_obj($self->{'pages'});

    return $t_page;
} # end of import_page()

=item $count = $pdf->pages()

Returns the number of pages in the document.

=cut

sub pages {
    my $self = shift;

    return scalar @{$self->{'pagestack'}};
}

=item $pdf->mediabox($name)

=item $pdf->mediabox($w,$h)

=item $pdf->mediabox($llx,$lly, $urx,$ury)

Sets the global mediabox.

B<Example:>

    $pdf = PDF::Builder->new();
    $pdf->mediabox('A4');
    ...
    $pdf->saveas('our/new.pdf');

    $pdf = PDF::Builder->new();
    $pdf->mediabox(595, 842);
    ...
    $pdf->saveas('our/new.pdf');

    $pdf = PDF::Builder->new;
    $pdf->mediabox(0, 0, 595, 842);
    ...
    $pdf->saveas('our/new.pdf');

=cut

sub mediabox {
    my ($self, $x1,$y1, $x2,$y2) = @_;

    $self->{'pages'}->{'MediaBox'} = PDFArray( map { PDFNum(float($_)) } page_size($x1,$y1, $x2,$y2));

    return $self;
}

=item $pdf->cropbox($name)

=item $pdf->cropbox($w,$h)

=item $pdf->cropbox($llx,$lly, $urx,$ury)

Sets the global cropbox.

=cut

sub cropbox {
    my ($self, $x1,$y1, $x2,$y2) = @_;

    $self->{'pages'}->{'CropBox'} = PDFArray( map { PDFNum(float($_)) } page_size($x1,$y1, $x2,$y2) );

    return $self;
}

=item $pdf->bleedbox($name)

=item $pdf->bleedbox($w,$h)

=item $pdf->bleedbox($llx,$lly, $urx,$ury)

Sets the global bleedbox.

=cut

sub bleedbox {
    my ($self, $x1,$y1, $x2,$y2) = @_;

    $self->{'pages'}->{'BleedBox'} = PDFArray( map { PDFNum(float($_)) } page_size($x1,$y1, $x2,$y2));

    return $self;
}

=item $pdf->trimbox($name)

=item $pdf->trimbox($w,$h)

=item $pdf->trimbox($llx,$lly, $urx,$ury)

Sets the global trimbox.

=cut

sub trimbox {
    my ($self, $x1,$y1, $x2,$y2) = @_;

    $self->{'pages'}->{'TrimBox'} = PDFArray( map { PDFNum(float($_)) } page_size($x1,$y1, $x2,$y2));

    return $self;
}

=item $pdf->artbox($name)

=item $pdf->artbox($w,$h)

=item $pdf->artbox($llx,$lly, $urx,$ury)

Sets the global artbox.

=cut

sub artbox {
    my ($self, $x1,$y1, $x2,$y2) = @_;

    $self->{'pages'}->{'ArtBox'} = PDFArray( map { PDFNum(float($_)) } page_size($x1,$y1, $x2,$y2) );

    return $self;
}

=back

=head1 FONT METHODS

=over

=item @directories = PDF::Builder::addFontDirs($dir1, $dir2, ...)

Adds one or more directories to the search path for finding font
files.

Returns the list of searched directories.

=cut

sub addFontDirs {
    my @dirs = @_;

    push @FontDirs, @dirs;

    return @FontDirs;
}

sub _findFont {
    my $font = shift;

    my @fonts = ($font, map { "$_/$font" } @FontDirs);
    shift @fonts while scalar(@fonts) and not -f $fonts[0];

    return $fonts[0];
}

=item $font = $pdf->corefont($fontname, %options)

=item $font = $pdf->corefont($fontname)

Returns a new Adobe core font object.

Core fonts are limited to single byte encodings. You cannot use UTF-8 or other
multibyte encodings with core fonts. The default encoding for the core fonts is
WinAnsiEncoding (roughly the CP-1252 superset of ISO-8859-1). See the 
C<-encode> option below to change this encoding.
See L<PDF::Builder::Resource::Font> C<automap> method for information on
accessing more than 256 glyphs in a font, using planes, I<although there is no
guarantee that future changes to font files will permit consistent results>.

Note that core fonts use fixed lists of expected glyphs, along with metrics
such as their widths. This may not exactly match up with whatever local font
file is used by the PDF reader. It's usually pretty close, but many cases have
been found where the list of glyphs is different between the core fonts and
various local font files, so be aware of this.

To allow UTF-8 text and extended glyph counts, you should 
consider replacing your use of core fonts with TrueType (.ttf) and OpenType
(.otf) fonts. There are tools, such as I<FontForge>, which can do a fairly good
(though, not perfect) job of converting a Type1 font library to OTF.

B<Examples:>

    $font1 = $pdf->corefont('Times-Roman', -encode => 'latin2');
    $font2 = $pdf->corefont('Times-Bold');
    $font3 = $pdf->corefont('Helvetica');
    $font4 = $pdf->corefont('ZapfDingbats');

Valid %options are:

=over

=item -encode

Changes the encoding of the font from its default. Notice that the encoding
(I<not> the entire font's glyph list) is shown in a PDF object (record), listing
256 glyphs associated with this encoding (I<and> that are available in this 
font). 

=item -dokern

Enables kerning if data is available.

=back

See Also: L<PDF::Builder::Resource::Font::CoreFont>.

=cut

sub corefont {
    my ($self, $name, %opts) = @_;

    require PDF::Builder::Resource::Font::CoreFont;
    my $obj = PDF::Builder::Resource::Font::CoreFont->new($self->{'pdf'}, $name, %opts);
    $self->{'pdf'}->out_obj($self->{'pages'});
    $obj->tounicodemap() if $opts{'-unicodemap'} == 1;

    return $obj;
}

=item $font = $pdf->psfont($ps_file, %options)

=item $font = $pdf->psfont($ps_file)

Returns a new Adobe Type1 ("PostScript") font object.

PS fonts are limited to single byte encodings. You cannot use UTF-8 or other
multibyte encodings with PS fonts.
The default encoding for the T1 fonts is
WinAnsiEncoding (roughly the CP-1252 superset of ISO-8859-1). See the 
C<-encode> option below to change this encoding.
See L<PDF::Builder::Resource::Font> C<automap> method for information on
accessing more than 256 glyphs in a font, using planes, I<although there is no
guarantee that future changes to font files will permit consistent results>.
B<Note:> most, if not
all, Type1 fonts appear to be limited to 256 glyphs anyway, but you might find 
one that has more than 256 glyphs and is not CID.

C<psfont> accepts both ASCII (.pfa) and binary (.pfb) Type1 glyph files.
Font metrics can be supplied in either ASCII (.afm) or binary (.pfm) format,
as can be seen in the examples given below.

To allow UTF-8 text and extended glyph counts in one font, you should 
consider replacing your use of Type1 fonts with TrueType (.ttf) and OpenType
(.otf) fonts. There are tools, such as I<FontForge>, which can do a fairly good
(though, not perfect) job of converting your font library to OTF.

B<Examples:>

    $font1 = $pdf->psfont('Times-Book.pfa', -afmfile => 'Times-Book.afm');
    $font2 = $pdf->psfont('/fonts/Synest-FB.pfb', -pfmfile => '/fonts/Synest-FB.pfm');

Valid %options are:

=over

=item -encode

Changes the encoding of the font from its default. Notice that the encoding
(I<not> the entire font's glyph list) is shown in a PDF object (record), listing
256 glyphs associated with this encoding (I<and> that are available in this 
font). 

=item -afmfile

Specifies the location of the font metrics file.

=item -pfmfile

Specifies the location of the printer font metrics file.  This option
overrides the -encode option.

=item -dokern

Enables kerning if data is available.

=back

=cut

sub psfont {
    my ($self, $psf, %opts) = @_;

    foreach my $o (qw(-afmfile -pfmfile)) {
        next unless defined $opts{$o};
        $opts{$o} = _findFont($opts{$o});
    }
    $psf = _findFont($psf);
    require PDF::Builder::Resource::Font::Postscript;
    my $obj = PDF::Builder::Resource::Font::Postscript->new($self->{'pdf'}, $psf, %opts);

    $self->{'pdf'}->out_obj($self->{'pages'});
    $obj->tounicodemap() if $opts{'-unicodemap'} == 1;

    return $obj;
}

=item $font = $pdf->ttfont($ttf_file, %options)

=item $font = $pdf->ttfont($ttf_file)

Returns a new TrueType or OpenType font object.

B<Warning:> BaseEncoding is I<not> set by default for TrueType fonts, so text 
in the PDF isn't searchable (by the PDF reader) unless a ToUnicode CMap is 
included. Include the ToUnicode CMap by default, but allow it to be disabled 
(for performance and file size reasons) by setting -unicodemap to 0. Note that 
non-searchable text, besides being annoying to users, may prevent screen 
readers and other aids to disabled users from working correctly!

B<Examples:>

    $font1 = $pdf->ttfont('Times.ttf');
    $font2 = $pdf->ttfont('Georgia.otf');

Valid %options are:

=over

=item -encode

Changes the encoding of the font from its default.

=item -isocmap

Use the ISO Unicode Map instead of the default MS Unicode Map.

=item -dokern

Enables kerning if data is available.

=item -noembed

Disables embedding of the font file.

=back

=cut

sub ttfont {
    my ($self, $file, %opts) = @_;

    # PDF::Builder doesn't set BaseEncoding for TrueType fonts, so text
    # isn't searchable unless a ToUnicode CMap is included.  Include
    # the ToUnicode CMap by default, but allow it to be disabled (for
    # performance and file size reasons) by setting -unicodemap to 0.
    $opts{'-unicodemap'} = 1 unless exists $opts{'-unicodemap'};

    $file = _findFont($file);
    require PDF::Builder::Resource::CIDFont::TrueType;
    my $obj = PDF::Builder::Resource::CIDFont::TrueType->new($self->{'pdf'}, $file, %opts);

    $self->{'pdf'}->out_obj($self->{'pages'});
    $obj->tounicodemap() if $opts{'-unicodemap'};

    return $obj;
}

=item $font = $pdf->cjkfont($cjkname, %options)

=item $font = $pdf->cjkfont($cjkname)

Returns a new CJK font object.

B<Examples:>

    $font = $pdf->cjkfont('korean');
    $font = $pdf->cjkfont('traditional');

Valid %options are:

=over

=item -encode

Changes the encoding of the font from its default.

=back

See Also: L<PDF::Builder::Resource::CIDFont::CJKFont>

=cut

sub cjkfont {
    my ($self, $name, %opts) = @_;

    require PDF::Builder::Resource::CIDFont::CJKFont;
    my $obj = PDF::Builder::Resource::CIDFont::CJKFont->new($self->{'pdf'}, $name, %opts);

    $self->{'pdf'}->out_obj($self->{'pages'});
    $obj->tounicodemap() if $opts{'-unicodemap'} == 1;

    return $obj;
}

=item $font = $pdf->synfont($basefont, %options)

=item $font = $pdf->synfont($basefont)

Returns a new synthetic font object. These are modifications to a core font,
where the font may be replaced by a Type1 or Type3 PostScript font.

B<Warning:> BaseEncoding is I<not> set by default for these fonts, so text 
in the PDF isn't searchable (by the PDF reader) unless a ToUnicode CMap is 
included. Include the ToUnicode CMap by default, but allow it to be disabled 
(for performance and file size reasons) by setting -unicodemap to 0. Note that 
non-searchable text, besides being annoying to users, may prevent screen 
readers and other aids to disabled users from working correctly!

B<Examples:>

    $cf  = $pdf->corefont('Times-Roman', -encode => 'latin1');
    $sf  = $pdf->synfont($cf, -slant => 0.85);  # compressed 85%
    $sfb = $pdf->synfont($cf, -bold => 1);      # embolden by 10em
    $sfi = $pdf->synfont($cf, -oblique => -12); # italic at -12 degrees

Valid %options are:

=over

=item -slant

Slant/expansion factor (0.1-0.9 = slant, 1.1+ = expansion).

=item -oblique

Italic angle (+/-)

=item -bold

Emboldening factor (0.1+, bold = 1, heavy = 2, ...)

=item -space

Additional character spacing in ems (0-1000)

=back

See Also: L<PDF::Builder::Resource::Font::SynFont>

=cut

sub synfont {
    my ($self, $font, %opts) = @_;

    # PDF::Builder doesn't set BaseEncoding for TrueType fonts, so text
    # isn't searchable unless a ToUnicode CMap is included.  Include
    # the ToUnicode CMap by default, but allow it to be disabled (for
    # performance and file size reasons) by setting -unicodemap to 0.
    $opts{'-unicodemap'} = 1 unless exists $opts{'-unicodemap'};

    require PDF::Builder::Resource::Font::SynFont;
    my $obj = PDF::Builder::Resource::Font::SynFont->new($self->{'pdf'}, $font, %opts);

    $self->{'pdf'}->out_obj($self->{'pages'});
    $obj->tounicodemap() if $opts{'-unicodemap'};

    return $obj;
}

=item $font = $pdf->bdfont($bdf_file, @options)

=item $font = $pdf->bdfont($bdf_file)

Returns a new BDF font object, based on the specified Adobe BDF file.

See Also: L<PDF::Builder::Resource::Font::BdFont>

=cut

sub bdfont {
    my ($self, @opts) = @_;

    require PDF::Builder::Resource::Font::BdFont;
    my $obj = PDF::Builder::Resource::Font::BdFont->new($self->{'pdf'}, @opts);

    $self->{'pdf'}->out_obj($self->{'pages'});
    # $obj->tounicodemap(); # does not support Unicode!

    return $obj;
}

=item $font = $pdf->unifont(@fontspecs, %options)

=item $font = $pdf->unifont(@fontspecs)

Returns a new uni-font object, based on the specified fonts and options.

B<BEWARE:> This is not a true PDF-object, but a virtual/abstract font definition!

See Also: L<PDF::Builder::Resource::UniFont>.

Valid %options are:

=over

=item -encode

Changes the encoding of the font from its default.

=back

=cut

sub unifont {
    my ($self, @opts) = @_;

    require PDF::Builder::Resource::UniFont;
    my $obj = PDF::Builder::Resource::UniFont->new($self->{'pdf'}, @opts);

    return $obj;
}

=back

=head1 IMAGE METHODS

=over

=item $jpeg = $pdf->image_jpeg($file)

Imports and returns a new JPEG image object.  C<$file> may be either a filename or a filehandle.

=cut

# =item $jpeg = $pdf->image_jpeg($file, %options)   no current options

sub image_jpeg {
    my ($self, $file, %opts) = @_;

    require PDF::Builder::Resource::XObject::Image::JPEG;
    my $obj = PDF::Builder::Resource::XObject::Image::JPEG->new($self->{'pdf'}, $file);

    $self->{'pdf'}->out_obj($self->{'pages'});

    return $obj;
}

=item $tiff = $pdf->image_tiff($file)

Imports and returns a new TIFF image object.  C<$file> may be either a filename or a filehandle.

=cut

# =item $tiff = $pdf->image_tiff($file, %options)   no current options

sub image_tiff {
    my ($self, $file, %opts) = @_;

    require PDF::Builder::Resource::XObject::Image::TIFF;
    my $obj = PDF::Builder::Resource::XObject::Image::TIFF->new($self->{'pdf'}, $file);
    $self->{'pdf'}->out_obj($self->{'pages'});

    return $obj;
}

=item $pnm = $pdf->image_pnm($file)

Imports and returns a new PNM image object.  C<$file> may be either a filename or a filehandle.

=cut

# =item $pnm = $pdf->image_pnm($file, %options)   no current options

sub image_pnm {
    my ($self, $file, %opts) = @_;

    require PDF::Builder::Resource::XObject::Image::PNM;
    my $obj = PDF::Builder::Resource::XObject::Image::PNM->new($self->{'pdf'}, $file);
    $self->{'pdf'}->out_obj($self->{'pages'});

    return $obj;
}

=item $png = $pdf->image_png($file)

Imports and returns a new PNG image object.  C<$file> may be either a filename or a filehandle.

=cut

# =item $png = $pdf->image_png($file, %options)   no current options

sub image_png {
    my ($self, $file, %opts) = @_;

    require PDF::Builder::Resource::XObject::Image::PNG;
    my $obj = PDF::Builder::Resource::XObject::Image::PNG->new($self->{'pdf'}, $file);
    $self->{'pdf'}->out_obj($self->{'pages'});
    
    return $obj;
}

=item $gif = $pdf->image_gif($file)

Imports and returns a new GIF image object.  C<$file> may be either a filename or a filehandle.

=cut

# =item $gif = $pdf->image_gif($file, %options)   no current options

sub image_gif {
    my ($self, $file, %opts) = @_;

    require PDF::Builder::Resource::XObject::Image::GIF;
    my $obj = PDF::Builder::Resource::XObject::Image::GIF->new($self->{'pdf'}, $file);
    $self->{'pdf'}->out_obj($self->{'pages'});

    return $obj;
}

=item $gdf = $pdf->image_gd($gd_object, %options)

=item $gdf = $pdf->image_gd($gd_object)

Imports and returns a new image object from Image::GD.

Valid %options are:

=over

=item -lossless => 1

Use lossless compression.

=back

=cut

sub image_gd {
    my ($self, $gd, %options) = @_;

    require PDF::Builder::Resource::XObject::Image::GD;
    my $obj = PDF::Builder::Resource::XObject::Image::GD->new($self->{'pdf'}, $gd, undef, %options);
    $self->{'pdf'}->out_obj($self->{'pages'});

    return $obj;
}

=back

=head1 COLORSPACE METHODS

=over

=item $cs = $pdf->colorspace_act($file)

Returns a new colorspace object based on an Adobe Color Table file.

See L<PDF::Builder::Resource::ColorSpace::Indexed::ACTFile> for a
reference to the file format's specification.

=cut

# =item $cs = $pdf->colorspace_act($file, %options)   no current options

sub colorspace_act {
    my ($self, $file, %opts) = @_;

    require PDF::Builder::Resource::ColorSpace::Indexed::ACTFile;
    my $obj = PDF::Builder::Resource::ColorSpace::Indexed::ACTFile->new($self->{'pdf'}, $file);
    $self->{'pdf'}->out_obj($self->{'pages'});

    return $obj;
}

=item $cs = $pdf->colorspace_web()

Returns a new colorspace-object based on the web color palette.

=cut

# =item $cs = $pdf->colorspace_web($file, %options)   no current options
# =item $cs = $pdf->colorspace_web($file)   no current file

sub colorspace_web {
    my ($self, $file, %opts) = @_;

    require PDF::Builder::Resource::ColorSpace::Indexed::WebColor;
    my $obj = PDF::Builder::Resource::ColorSpace::Indexed::WebColor->new($self->{'pdf'});
    $self->{'pdf'}->out_obj($self->{'pages'});

    return $obj;
}

=item $cs = $pdf->colorspace_hue()

Returns a new colorspace-object based on the hue color palette.

See L<PDF::Builder::Resource::ColorSpace::Indexed::Hue> for an explanation.

=cut

# =item $cs = $pdf->colorspace_hue($file, %options)   no current options
# =item $cs = $pdf->colorspace_hue($file)   no current file

sub colorspace_hue {
    my ($self, $file, %opts) = @_;

    require PDF::Builder::Resource::ColorSpace::Indexed::Hue;
    my $obj = PDF::Builder::Resource::ColorSpace::Indexed::Hue->new($self->{'pdf'});
    $self->{'pdf'}->out_obj($self->{'pages'});

    return $obj;
}

=item $cs = $pdf->colorspace_separation($tint, $color)

Returns a new separation colorspace object based on the parameters.

I<$tint> can be any valid ink identifier, including but not limited
to: 'Cyan', 'Magenta', 'Yellow', 'Black', 'Red', 'Green', 'Blue' or
'Orange'.

I<$color> must be a valid color specification limited to: '#rrggbb',
'!hhssvv', '%ccmmyykk' or a "named color" (rgb).

The colorspace model will automatically be chosen based on the
specified color.

=cut

sub colorspace_separation {
    my ($self, $tint, @clr) = @_;

    require PDF::Builder::Resource::ColorSpace::Separation;
    my $obj = PDF::Builder::Resource::ColorSpace::Separation->new($self->{'pdf'}, pdfkey(), $tint, @clr);
    $self->{'pdf'}->out_obj($self->{'pages'});

    return $obj;
}

=item $cs = $pdf->colorspace_devicen(\@tintCSx, $samples)

=item $cs = $pdf->colorspace_devicen(\@tintCSx)

Returns a new DeviceN colorspace object based on the parameters.

B<Example:>

    $cy = $pdf->colorspace_separation('Cyan',    '%f000');
    $ma = $pdf->colorspace_separation('Magenta', '%0f00');
    $ye = $pdf->colorspace_separation('Yellow',  '%00f0');
    $bk = $pdf->colorspace_separation('Black',   '%000f');

    $pms023 = $pdf->colorspace_separation('PANTONE 032CV', '%0ff0');

    $dncs = $pdf->colorspace_devicen( [ $cy,$ma,$ye,$bk, $pms023 ] );

The colorspace model will automatically be chosen based on the first
colorspace specified.

=cut

sub colorspace_devicen {
    my ($self, $clrs, $samples) = @_;
    $samples ||= 2;

    require PDF::Builder::Resource::ColorSpace::DeviceN;
    my $obj = PDF::Builder::Resource::ColorSpace::DeviceN->new($self->{'pdf'}, pdfkey(), $clrs, $samples);
    $self->{'pdf'}->out_obj($self->{'pages'});

    return $obj;
}

=back

=head1 BARCODE METHODS

These are glue routines to the actual barcode rendering routines found
elsewhere.

=over

=item $bc = $pdf->xo_codabar(%options)

=item $bc = $pdf->xo_code128(%options)

=item $bc = $pdf->xo_2of5int(%options)

=item $bc = $pdf->xo_3of9(%options)

=item $bc = $pdf->xo_ean13(%options)

Creates the specified barcode object as a form XObject.

=cut

# TBD consider moving these to a BarCodes subdirectory, as the number of bar
# code routines increases

sub xo_code128 {
    my ($self, @options) = @_;

    require PDF::Builder::Resource::XObject::Form::BarCode::code128;
    my $obj = PDF::Builder::Resource::XObject::Form::BarCode::code128->new($self->{'pdf'}, @options);
    $self->{'pdf'}->out_obj($self->{'pages'});

    return $obj;
}

sub xo_codabar {
    my ($self, @options) = @_;

    require PDF::Builder::Resource::XObject::Form::BarCode::codabar;
    my $obj = PDF::Builder::Resource::XObject::Form::BarCode::codabar->new($self->{'pdf'}, @options);
    $self->{'pdf'}->out_obj($self->{'pages'});

    return $obj;
}

sub xo_2of5int {
    my ($self, @options) = @_;

    require PDF::Builder::Resource::XObject::Form::BarCode::int2of5;
    my $obj = PDF::Builder::Resource::XObject::Form::BarCode::int2of5->new($self->{'pdf'}, @options);
    $self->{'pdf'}->out_obj($self->{'pages'});

    return $obj;
}

sub xo_3of9 {
    my ($self, @options) = @_;

    require PDF::Builder::Resource::XObject::Form::BarCode::code3of9;
    my $obj = PDF::Builder::Resource::XObject::Form::BarCode::code3of9->new($self->{'pdf'}, @options);
    $self->{'pdf'}->out_obj($self->{'pages'});

    return $obj;
}

sub xo_ean13 {
    my ($self, @options) = @_;

    require PDF::Builder::Resource::XObject::Form::BarCode::ean13;
    my $obj = PDF::Builder::Resource::XObject::Form::BarCode::ean13->new($self->{'pdf'}, @options);
    $self->{'pdf'}->out_obj($self->{'pages'});

    return $obj;
}

=back

=head1 OTHER METHODS

=over

=item $xo = $pdf->xo_form()

Returns a new form XObject.

=cut

sub xo_form {
    my $self = shift;

    my $obj = PDF::Builder::Resource::XObject::Form::Hybrid->new($self->{'pdf'});
    $self->{'pdf'}->out_obj($self->{'pages'});

    return $obj;
}

=item $egs = $pdf->egstate()

Returns a new extended graphics state object.

=cut

sub egstate {
    my $self = shift;

    my $obj = PDF::Builder::Resource::ExtGState->new($self->{'pdf'}, pdfkey());
    $self->{'pdf'}->out_obj($self->{'pages'});

    return $obj;
}

=item $obj = $pdf->pattern(%options)

=item $obj = $pdf->pattern()

Returns a new pattern object.

=cut

sub pattern {
    my ($self, %options) = @_;

    my $obj = PDF::Builder::Resource::Pattern->new($self->{'pdf'}, undef, %options);
    $self->{'pdf'}->out_obj($self->{'pages'});

    return $obj;
}

=item $obj = $pdf->shading(%options)

=item $obj = $pdf->shading()

Returns a new shading object.

=cut

sub shading {
    my ($self, %options) = @_;

    my $obj = PDF::Builder::Resource::Shading->new($self->{'pdf'}, undef, %options);
    $self->{'pdf'}->out_obj($self->{'pages'});

    return $obj;
}

=item $otls = $pdf->outlines()

Returns a new or existing outlines object.

=cut

sub outlines {
    my $self = shift;

    require PDF::Builder::Outlines;
    $self->{'pdf'}->{'Root'}->{'Outlines'} ||= PDF::Builder::Outlines->new($self);

    my $obj = $self->{'pdf'}->{'Root'}->{'Outlines'};

    $self->{'pdf'}->new_obj($obj) unless $obj->is_obj($self->{'pdf'});
    $self->{'pdf'}->out_obj($obj);
    $self->{'pdf'}->out_obj($self->{'pdf'}->{'Root'});

    return $obj;
}

=item $ndest = $pdf->named_destination()

Returns a new or existing named destination object.

=cut

sub named_destination {
    my ($self, $cat, $name, $obj) = @_;
    my $root=$self->{'catalog'};

    $root->{'Names'} ||= PDFDict();
    $root->{'Names'}->{$cat} ||= PDFDict();
    $root->{'Names'}->{$cat}->{'-vals'} ||= {};
    $root->{'Names'}->{$cat}->{'Limits'} ||= PDFArray();
    $root->{'Names'}->{$cat}->{'Names'} ||= PDFArray();

    unless (defined $obj) {
        $obj = PDF::Builder::NamedDestination->new($self->{'pdf'});
    }
    $root->{'Names'}->{$cat}->{'-vals'}->{$name} = $obj;

    my @names = sort {$a cmp $b} keys %{$root->{'Names'}->{$cat}->{'-vals'}};

    $root->{'Names'}->{$cat}->{'Limits'}->{' val'}->[0] = PDFStr($names[0]);
    $root->{'Names'}->{$cat}->{'Limits'}->{' val'}->[1] = PDFStr($names[-1]);

    @{$root->{'Names'}->{$cat}->{'Names'}->{' val'}} = ();

    foreach my $k (@names) {
        push @{$root->{'Names'}->{$cat}->{'Names'}->{' val'}},
        (   PDFStr($k),
            $root->{'Names'}->{$cat}->{'-vals'}->{$k}
        );
    }

    return $obj;
} # end of named_destination()

1;

__END__

=back

=head1 KNOWN ISSUES

This module does not work with perl's -l command-line switch.

=head1 AUTHOR

PDF::API2 was originally written by Alfred Reibenschuh.

It was maintained by Steve Simms.

PDF::Builder is currently being maintained by Phil M. Perry.

Full source is on https://github.com/PhilterPaper/Perl-PDF-Builder

Bug reports are on https://github.com/PhilterPaper/Perl-PDF-Builder/issues?q=is%3Aissue+sort%3Aupdated-desc and general discussions are on http://www.catskilltech.com/forum/pdf-builder-general-discussions/. Please do not use the RT.cpan system to report issues, as it is not regularly monitored.

Release distribution is on CPAN: https://metacpan.org/pod/PDF::Builder

=cut
