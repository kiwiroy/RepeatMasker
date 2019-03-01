#!/u1/local/bin/perl
##---------------------------------------------------------------------------##
##  File:
##      @(#) LibraryUtils.pm
##  Author:
##      Robert M. Hubley   rhubley@systemsbiology.org
##  Description:
##      Module to assist in the validation and updating of
##      RepeatMasker's growing set of library files.
##
#******************************************************************************
#* Copyright (C) Institute for Systems Biology 2017-2017 Developed by
#* Arian Smit and Robert Hubley.
#*
#* This work is licensed under the Open Source License v2.1.  To view a copy
#* of this license, visit http://www.opensource.org/licenses/osl-2.1.php or
#* see the license.txt file contained in this distribution.
#*
#******************************************************************************
#
# ChangeLog
#
#     $Log$
#
###############################################################################
#
# To Do:
#

=head1 NAME

LibraryUtils.pm - Validate and update RepeatMasker libaries

=head1 SYNOPSIS

use LibraryUtils;

Usage:

LibraryUtils::validate()

=head1 DESCRIPTION

  A set of subroutines to assist RepeatMasker with managing the installation
  of multiple repeat libraries.

The options are:

=head1 INSTANCE METHODS

=cut

#
# Module Dependence
#
package LibraryUtils;
use strict;
use FindBin;
use lib $FindBin::Bin;
use Getopt::Long;
use Data::Dumper;
use EMBL;
use DFAM;
use File::Basename;

my $DEBUG = 0;

use vars qw(@ISA @EXPORT @EXPORT_OK %EXPORT_TAGS $VERSION);
require Exporter;

@ISA = qw(Exporter);

@EXPORT = qw();

@EXPORT_OK = qw();

%EXPORT_TAGS = ( all => [ @EXPORT_OK ] );

##-------------------------------------------------------------------------##

=begin

=over 4

=item my $versionString = getLibraryVersionStr( $libFile );

Return the version from the header of the given library file.

=back

=cut

##-------------------------------------------------------------------------##
sub getLibraryVersionStr {
  my $libFile = shift;

  open INVER, "<$libFile"
      or die "getLibraryVersion(): Could not open file $libFile";
  my $releaseStr  = "";
  my $searchLimit = 50;    # 50 lines max
  while ( <INVER> ) {

    # RepBase RepeatMasker Edition
    #    CC   RELEASE 20170125;
    # Dfam.hmm
    #    #    Release: Dfam_2.0
    # Dfam.embl
    #    CC   Release: Dfam_3.0
    if (    /^(?:CC|#)\s+Release:\s+(Dfam_\S+).*/
         || /^(?:CC|##)\s+RELEASE\s+(\S+);.*/ )
    {
      $releaseStr = $1;
      last;
    }
    last if ( $searchLimit-- == 0 );
  }
  close INVER;

  return $releaseStr;
}

sub getCombinedLibrarySources {
  my $libFile = shift;

  open INVER, "<$libFile"
      or die "getLibraryVersion(): Could not open file $libFile";
  my %sources     = ();
  my $searchLimit = 50;    # 50 lines max
  my $inSources   = 0;
  while ( <INVER> ) {
    $inSources = 1 if ( /^CC\s+Sources:.*/ );
    # CC   Artefacts RELEASE: 20170125;
    # CC   Dfam RELEASE: Dfam_3.0;
    # CC   Dfam_Consensus RELEASE 20170125;
    # CC   RepBase RELEASE 20170125;
    if ( /^CC\s+(\S+)\s+RELEASE\s+(\S+);.*/ ) {
      $sources{$1} = $2;
    }
    last if ( $searchLimit-- == 0 || ( $inSources && /^CC\s*$/ ) );
  }
  close INVER;

  return \%sources;
}

sub validateLibraries {
  # Interrogate the Libraries subdirectory
  my $libDir  = shift;
  my $libType = shift;

  # Old filestructure ( pre-2017 )
  #   /Libraries
  #     RepeatMaskerLib.embl         : RepBase RepeatMasker Edition
  #                                    or
  #                                    Minimal RepeatMasker Library containing only
  #                                    non-RepBase repeats
  #     Dfam.hmm                     : Dfam library ( no processing necessary )
  #
  # Intermediate filestructure ( Dfam_consensus, RM.. )
  #    /Libraries
  #         RepeatMaskerLib.embl     : The combined libraries for RepeatMasker
  #         DfamConsensus.embl       : The Dfam Consensus library
  #                                    ( which now contains the Minimal RM Library )
  #         RMRBMeta.embl            : The RepeatMasker Metadata for Repbase
  #         RMRBSeqs.embl            : RepBase Library ( RepeatMasker Edition ) from GIRI
  #         Dfam.hmm                 : Dfam library ( no processing necessary )
  #        
  # Dfam filestructure ( 2019 )
  #    /Libraries
  #         RepeatMaskerLib.embl     : The combined libraries for RepeatMasker.  This file
  #                                    is generated by the RepeatMasker/configure script using
  #                                    data from the individual libraries below.
  #         Artefacts.embl           : A RepeatMaker supplied file containing common DNA
  #                                    cloning vectors and other non-genomic artefacts.
  #         Dfam.hmm                 : Dfam HMM library ( no processing necessary )
  #         Dfam.embl                : The Dfam library in consensus format.
  #         RMRBMeta.embl            : The RepeatMasker Metadata for Repbase.
  #         RMRBSeqs.embl            : RepBase Library ( RepeatMasker Edition ) obtainable 
  #                                    from GIRI with a paid license.
  #                      
  my $mainLibrary          = "RepeatMaskerLib.embl";
  my $artefactsLibrary     = "Artefacts.embl";
  my $dfamCONLibrary       = "Dfam.embl";
  my $dfamHMMLibrary       = "Dfam.hmm";
  my $RBRMSeqLibrary       = "RMRBSeqs.embl";
  my $RBRMMetaLibrary      = "RMRBMeta.embl";

  my %dbAlias = (
                  'Dfam'           => '',
                  'RepBase'        => 'rb'
  );

  my $rmLibraryVersionKey  = "";
  my $isLibraryCombined    = 0;
  my $rmLibraryDescription = "";

  if ( $libType eq "HMM" ) {
    if ( -s "$libDir/$dfamHMMLibrary" ) {
      my $dfamVersion = getLibraryVersionStr( "$libDir/$dfamHMMLibrary" );
      $rmLibraryVersionKey  = $dfamVersion;
      $rmLibraryDescription = "Dfam database version $dfamVersion";
    }
    else {
      print
          "\n\nThe Dfam Profile HMM library ( $libDir/$dfamHMMLibrary ) was not\n"
          . "found.  Please download and install the latest version from\n"
          . "http://www.dfam.org.\n\n";
      die;
    }
  }
  else {

    # Do we have a main consensus library file?
    if ( -s "$libDir/$mainLibrary" ) {

      # Which structure do we have?
      my $libSources = getCombinedLibrarySources( "$libDir/$mainLibrary" );
      if ( defined $libSources && keys( %{$libSources} ) ) {

        # Main library file is a combined library ( new structure )
        $isLibraryCombined = 1;

        # Validate RepBase RepeatMasker Edition
        my $mustRebuild = 0;
        if ( -s "$libDir/$RBRMSeqLibrary" ) {

          # Validate that we have included RepBase
          my $rbSeqVersion = getLibraryVersionStr( "$libDir/$RBRMSeqLibrary" );
          if ( $rbSeqVersion ne $libSources->{'RepBase'} ) {

            #
            my $rmRbMetaVersion;
            if ( -s "$libDir/$RBRMMetaLibrary" ) {
              $rmRbMetaVersion =
                  getLibraryVersionStr( "$libDir/$RBRMMetaLibrary" );
              $rmRbMetaVersion = undef if ( $rmRbMetaVersion ne $rbSeqVersion );
            }
            if ( !$rmRbMetaVersion ) {
              print
                  "\n\nThe Repbase RepeatMasker Edition database has changed\n"
                  . "( RELEASE = $rbSeqVersion ), however the corresponding\n"
                  . "metadata library file ( $libDir/$RBRMMetaLibrary ) is missing or\n"
                  . "out of date.  Please obtain the metadata library from:\n"
                  . "http:/www.repeatmasker.org/libraries/RepeatMaskerMetaData-$rbSeqVersion.tar.gz\n"
                  . "Once this file is in placed in $libDir rerun RepeatMasker to continue.\n\n";
              die;
            }
            print
"RepBase RepeatMasker Edition database changed ( RELEASE = $rbSeqVersion ).\n";
            $mustRebuild = 1;
          }
        }

        # Validate Artefacts.embl
        if ( -s "$libDir/$artefactsLibrary" ) {
          my $artVersion = getLibraryVersionStr( "$libDir/$artefactsLibrary" );
          if ( $artVersion ne $libSources->{'Artefacts'} ) {
            print "RepeatMasker Artefacts database changed ( RELEASE = $artVersion ).\n";
            $mustRebuild = 1;
          }
        }

        # Validate Dfam.embl
        if ( -s "$libDir/$dfamCONLibrary" ) {

          # Validate that we have included Dfam
          my $dfamConsVersion =
              getLibraryVersionStr( "$libDir/$dfamCONLibrary" );
          if ( $dfamConsVersion ne $libSources->{'Dfam'} ) {
            print "Dfam database changed ( RELEASE = $dfamConsVersion ).\n";
            $mustRebuild = 1;
          }
        }
        if ( $mustRebuild ) {
          rebuildMainLibrary( $libDir );
          $libSources = getCombinedLibrarySources( "$libDir/$mainLibrary" );
        }
        
        delete $libSources->{'Artefacts'};

        $rmLibraryVersionKey = join( "-",
                                     map { $dbAlias{$_} . $libSources->{$_} }
                                         sort keys( %{$libSources} ) );
        $rmLibraryDescription = "RepeatMasker Combined Database: "
            . join( ", ",
                    map { $_ . "-" . $libSources->{$_} }
                        sort keys( %{$libSources} ) );
      }
      else {
        # LEGACY SUPPORT
        # Main library is either a minimal library or a older
        # RepBase RepeatMasker Edition file
        my $isMinimum    = 0;
        my $rmlibVersion = getLibraryVersionStr( "$libDir/$mainLibrary" );
        if ( $rmlibVersion =~ /(\d+)-min/ ) {
          $rmlibVersion = $1;
          $isMinimum    = 1;
        }
        if ( $rmlibVersion && $rmlibVersion <= 20160829 ) {
          # Last valid version for legacy structure
          # Check to see if we have newer files in the directory and
          # warn that they are not being used.
          my @extraLibs;
          push @extraLibs, $dfamCONLibrary
              if ( -s "$libDir/$dfamCONLibrary" );
          push @extraLibs, $RBRMSeqLibrary if ( -s "$libDir/$RBRMSeqLibrary" );
          if ( @extraLibs ) {
            print "\n\nNewer libraries exist in $libDir: "
                . join( ", ", @extraLibs ) . "\n"
                . "but are not configured for use by RepeatMasker.  To enable them, remove\n"
                . "the $libDir/$mainLibrary file and rerun RepeatMasker to rebuild it.\n\n";
            die;
          }
          print
              "Legacy format: rmlibVersion = $rmlibVersion.  Ok to continue\n";
        }
        else {
          die "Legacy file format for $libDir/$mainLibrary yet\n"
              . "version ( $rmlibVersion ) is not valid.";
        }
        $rmLibraryVersionKey  = $rmlibVersion;
        $rmLibraryDescription =
            "RepBase/RepeatMasker database version $rmlibVersion";
        $rmLibraryDescription .= "-min" if ( $isMinimum );
        # Used to be
        # "RepBase Update $rmLibraryVersion, RM database version $rmLibraryVersion";
      }
    }
    else {
      # We don't have a main library file
      if ( -s "$libDir/$dfamCONLibrary" || -s "$libDir/$RBRMSeqLibrary" )
      {
        $isLibraryCombined = 1;
        rebuildMainLibrary( $libDir );
        my $libSources = getCombinedLibrarySources( "$libDir/$mainLibrary" );
        delete $libSources->{'Artefacts'};
        $rmLibraryVersionKey = join( "-",
                                     map { $dbAlias{$_} . $libSources->{$_} }
                                         sort keys( %{$libSources} ) );
        $rmLibraryDescription = "RepeatMasker Combined Database: "
            . join( ", ",
                    map { $_ . "-" . $libSources->{$_} }
                        sort keys( %{$libSources} ) );

      }
      else {
        print
            "\n\nNo repeat libraries found!  At a minimum the Dfam_consensus\n"
            . "is required to run.  Please download and install the latest \n"
            . "Dfam_consensus.  It is highly recommended that you also install the\n"
            . "latest RepBase RepeatMasker Edition library obtainable from GIRI.\n"
            . "General instructions can be found here: http://www.repeatmasker.org\n\n";
        die;
      }
    }
  }
  return ( $isLibraryCombined, $rmLibraryVersionKey, $rmLibraryDescription );
}

sub rebuildMainLibrary {
  my $libDir = shift;

  my $mainLibrary          = "RepeatMaskerLib.embl";
  my $dfamCONLibrary       = "Dfam.embl";
  my $artefactsLibrary     = "Artefacts.embl";
  my $RBRMSeqLibrary       = "RMRBSeqs.embl";
  my $RBRMMetaLibrary      = "RMRBMeta.embl";

  print "Rebuilding $mainLibrary library\n";

  # Backup old library ( only one backup kept )
  unlink( "$libDir/$mainLibrary.old" )
      if ( -s "$libDir/$mainLibrary.old" );
  rename( "$libDir/$mainLibrary", "$libDir/$mainLibrary.old" )
      if ( -s "$libDir/$mainLibrary" );

  my $headerSources = "";

  my $combinedDb = new EMBL();

  if ( -s "$libDir/$artefactsLibrary" ) {
    my $savBuf = $|;
    $| = 1;
    print "    Reading Artefacts.embl database...";
    $| = $savBuf;
    my $db = EMBL->new( fileName => "$libDir/$artefactsLibrary" );
    print "\r  - Read in "
        . $db->size()
        . " sequences from $libDir/$artefactsLibrary\n";
    $combinedDb->addAll( $db );
    my $libVersion = getLibraryVersionStr( "$libDir/$artefactsLibrary" );
    $headerSources .= "CC    Artefacts RELEASE $libVersion;                                 *\n";
  }

  my %dfam2xNames = ();
  if ( -s "$libDir/$dfamCONLibrary" ) {
    my $savBuf = $|;
    $| = 1;
    print "    Reading Dfam.embl database...";
    $| = $savBuf;
    my $db = EMBL->new( fileName => "$libDir/$dfamCONLibrary" );
    my $seqCount = $db->size();
    for ( my $i = 0 ; $i < $seqCount ; $i++ ) {
      my $rec = $db->get( $i );
      my $id = $rec->getId();
      my $name = $rec->getName();
      if ( $id =~ /DF(\d+)/ ){
        # DF0004191 is the last Dfam 2.x family
        if ( $1 <= 4191 ) {
          $dfam2xNames{$name} = $id;
        }
      }else { die "Something is wrong with the $libDir/$dfamCONLibrary file.  Expected a Dfam ID but got $id\n"; }
    }
    print "\r  - Read in "
        . $db->size()
        . " sequences from $libDir/$dfamCONLibrary\n";
    $combinedDb->addAll( $db );
    my $libVersion = getLibraryVersionStr( "$libDir/$dfamCONLibrary" );
    $headerSources .= "CC    Dfam RELEASE $libVersion;                                      *\n";
  }

  if ( -s "$libDir/$RBRMSeqLibrary" ) {
    my $savBuf = $|;
    $| = 1;
    print "    Reading RepBase RepeatMasker Edition database...";
    $| = $savBuf;
    my $seqs = EMBL->new( fileName => "$libDir/$RBRMSeqLibrary" );
    my %seqId = ();
    for ( my $i = 0 ; $i < $seqs->size() ; $i++ ) {
      my $rec = $seqs->get( $i );
      # Do not include families already provided by Dfam.
      # NOTE: We may want to make a way to search either or both
      #       at some point in the future.
      if ( ! exists $dfam2xNames{ $rec->getId() } ) 
      {
        $seqId{ $rec->getId() } = $rec;
      }
    }
    print "\r  - Read in "
        . $seqs->size()
        . " sequences ( kept " . scalar(keys %seqId) . " ) from $libDir/$RBRMSeqLibrary\n";
    undef $seqs;

    my $libVersion = getLibraryVersionStr( "$libDir/$RBRMSeqLibrary" );
    $headerSources .=
"CC    RepBase RELEASE $libVersion;                                   *";

    my $savBuf = $|;
    $| = 1;
    print "    Reading metadata database...";
    $| = $savBuf;
    my $meta = EMBL->new( fileName => "$libDir/$RBRMMetaLibrary" );
    my $numMerged = 0;
    for ( my $i = 0 ; $i < $meta->size() ; $i++ ) {
      my $mRec = $meta->get( $i );
      my $sRec = $seqId{ $mRec->getId() };
      if ( $mRec && $sRec ) {
        $mRec->setLength( $sRec->getLength() );
        $mRec->setSequence( $sRec->getSequence() );
        $mRec->setComposition( 'A', $sRec->getCompositionElement( 'A' ) );
        $mRec->setComposition( 'C', $sRec->getCompositionElement( 'C' ) );
        $mRec->setComposition( 'G', $sRec->getCompositionElement( 'G' ) );
        $mRec->setComposition( 'T', $sRec->getCompositionElement( 'T' ) );
        $mRec->setComposition( 'other',
                               $sRec->getCompositionElement( 'other' ) );
        $mRec->pushComments( "Source: RepBase RepeatMasker Edition\n" );
        $combinedDb->add( $mRec );
        $numMerged++;
      }
      elsif ( exists $dfam2xNames{ $mRec->getId() } ) {
        # As expected.
      }
      else {
        print "Error! Could not find " . $mRec->getId() . "\n";
      }
    }
    print "\r  - Read in "
        . $meta->size()
        . " annotations ( merged $numMerged ) from $libDir/$RBRMMetaLibrary\n";
    #$combinedDb->addAll( $meta );
  }

  my $savBuf = $|;
  $| = 1;
  print "  Saving $mainLibrary library...";
  $| = $savBuf;
  my $headerStr =
      "CC ****************************************************************
CC                                                                *
CC   RepeatMasker Combined Library                                *
CC    This is a merged file of external library sources.          *
CC    See the original libraries for detailed copyright           *
CC    and licensing restrictions.                                 *
CC                                                                *
CC   Sources:                                                     *
$headerSources
CC                                                                *
CC   RepeatMasker software, and maintenance are currently         *
CC   funded by an NIH/NHGRI R01 grant HG02939-01 to Arian Smit.   *
CC                                                                *
CC   Dfam software, database development and maintenance          *
CC   are currently funded by the National Human Genome            *
CC   Research Institute (NHGRI grant # U24 HG010136).             *
CC   Please see the Dfam.hmm/Dfam.embl files for more             *
CC   information or go to http://www.dfam.org.                    *
CC                                                                *
CC ****************************************************************";

  $combinedDb->writeEMBLFile( "$libDir/$mainLibrary", $headerStr );
  print "\r$mainLibrary: " . $combinedDb->size() . " total sequences.\n";

}

1;
