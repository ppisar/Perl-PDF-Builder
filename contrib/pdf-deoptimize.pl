#!/usr/bin/perl

use strict;
use warnings;

our $VERSION = '3.005'; # VERSION
my $LAST_UPDATE = '2.029'; # manually update whenever code is changed

use PDF::Builder::Basic::PDF::File;
use PDF::Builder::Basic::PDF::Utils;
use PDF::Builder;
use Compress::Zlib;
use Scalar::Util qw(blessed);

sub walk_obj {
    my ($objs,$spdf,$tpdf,$obj,@keys)=@_;

    my $tobj;

    if(ref($obj)=~/Objind$/) {
        $obj->realise;
    }

    return($objs->{scalar $obj}) if(defined $objs->{scalar $obj});

  die "object already copied" if(   $obj->{' copied'});

    $tobj=$obj->copy($spdf);
    $obj->{' copied'}=1;
    $tpdf->new_obj($tobj) if($obj->is_obj($spdf) && !$tobj->is_obj($tpdf));

  $objs->{scalar $obj}=$tobj;

    if(ref($obj)=~/Array$/ || (blessed($obj) && $obj->isa('PDF::Builder::Basic::PDF::Array'))) {
        $tobj->{' val'}=[];
        foreach my $k ($obj->elementsof) {
            $k->realise if(ref($k)=~/Objind$/);
            $tobj->add_elements(walk_obj($objs,$spdf,$tpdf,$k));
        }
    } elsif(ref($obj)=~/Dict$/ || (blessed($obj) && $obj->isa('PDF::Builder::Basic::PDF::Dict'))) {
        @keys=keys(%{$tobj}) if(scalar @keys <1);
        foreach my $k (@keys) {
            next if($k=~/^ /);
            next unless(defined($obj->{$k}));
            $tobj->{$k}=walk_obj($objs,$spdf,$tpdf,$obj->{$k});
        }
        if($obj->{' stream'}) {
            if($tobj->{Filter} && !$tobj->{DecodeParms}) {
                my $f=$tobj->{Filter};
                $f=PDFArray($f) unless(ref($f)=~/Array/);
                if(scalar($f->elementsof) == 1) {
                    my ($t)=$f->elementsof;
                    if($t->val eq 'FlateDecode') {
                        $tobj->{' stream'}=uncompress($obj->{' stream'});
                        delete $tobj->{Filter};
                        $tobj->{Length}=PDFNum(length($tobj->{' stream'}));
                    } else {
                        $tobj->{' stream'}=$obj->{' stream'};
                    }
                } else {
                    $tobj->{' stream'}=$obj->{' stream'};
                }
                $tobj->{' nofilt'}=1;
            } else {
                $tobj->{' stream'}=$obj->{' stream'};
            }
        }
    }
    delete $tobj->{' streamloc'};
    delete $tobj->{' streamsrc'};
    return($tobj);
}

if(scalar @ARGV<2) {
    print "usage: $0 infile outfile\n";
    exit(1);
}
my $spdf=PDF::Builder::Basic::PDF::File->open($ARGV[0]);
my $tpdf=PDF::Builder::Basic::PDF::File->_new;
my $mycache={};
$tpdf->{Root}=walk_obj($mycache,$spdf,$tpdf,$spdf->{Root});
$tpdf->{Info}=walk_obj($mycache,$spdf,$tpdf,$spdf->{Info}) if $spdf->{Info};

$tpdf->out_file($ARGV[1]);
