######################################################################
#
#  Web of Science citation ingest.
#
#  This plug-in retrieves citation data from the WoS Starter API.
#  It is called by Queensland University of Technology Citation Count 
#  Dataset and Import plug-ins for EPrints 3.
#
#  Part of https://uzh-it.atlassian.net/browse/ZORA-1061
# 
######################################################################
#
#  Copyright 2023 University of Zurich. All Rights Reserved.
#
#  Martin Brändle
#  Zentrale Informatik
#  Universität Zürich
#  Stampfenbachstr. 73
#  CH-8006 Zürich
#
#  Initial:
#  2023/07/26
#
#  Modified:
#  2023/08/22/mb mask DOI, mask SAME operator
#
#  The plug-ins are free software; you can redistribute them and/or modify
#  them under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The plug-ins are distributed in the hope that they will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with EPrints 3; if not, write to the Free Software
#  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
#
######################################################################

=pod

=head1 NAME

EPrints::Plugin::Import::CitationService::WoS - Plug-in for WoS citation ingest.

=head1 DESCRIPTION

This plug-in retrieves citation data from the WoS Starter API.
It is called by the Queensland University of Technology Citation Count 
Dataset and Import plug-ins for EPrints 3.


=head1 METHODS

=over 4

=item $plugin = EPrints::Plugin::Import::CitationImport::WoS->new( %params )

Creates a new Import::CitationService::WoS plugin. Should not be called directly, but via $session->plugin.

=cut


package EPrints::Plugin::Import::CitationService::WoS;

use strict;
use warnings;
use utf8;

use lib '/usr/local/eprints/perl_cpan/lib/perl5';

use JSON;
use LWP::UserAgent;
use URI::Escape;
use HTTP::Status qw(:constants :is status_message);


use base 'EPrints::Plugin::Import::CitationService';

#
# Create a new plug-in object.
#
sub new
{
	my ($class, %params) = @_;

	my $self = $class->SUPER::new( %params );

	# set some parameters
	$self->{name} = "Web of Science(R) Citation Ingest";
	
	$self->{apiurl} = $self->param( "baseurl" );
	$self->{apikey} = $self->param( "apikey" );
	$self->{requestsize} = $self->param( "requestsize" );
	$self->{requestsize} ||= 50;
	$self->{maxrequests} = $self->param( "maxrequests" );
	$self->{maxrequests} ||= 5000;
	$self->{types} = $self->param( "types" );
	$self->{doifield} =  $self->param( "doifieldname" );
	$self->{doifield} ||= "id_number";
	$self->{pmidfield} = $self->param( "pmidfieldname" );
	$self->{pmidfield} ||= "id_number";
	$self->{query} = "";
	$self->{sendquery} = 0;
	$self->{carryforward} = 0;
	$self->{querylength} = 0;
	$self->{queryfields} = $self->param( "queryfields" );
	$self->{queryset} = [];
	$self->{citedata} = [];

	return $self;
}

#
# Retrieve citation counts for all $opts{eprintids} and
# returns a list of IDs successfully retrieved.
# Each WoS API query processes a batch of eprint items, at maximum 50
#
sub process_eprints
{
    my( $plugin, %opts ) = @_;
    
    my $eprintids = $opts{eprintids};

    my @ids;
    
    my $query;
    
    my $query_count = 0;
    my $count = 0;
    my $total = scalar(@{$eprintids});
    foreach my $eprintid (@{$eprintids})
    {
    	$count++;
    	my $eprint = $plugin->{session}->eprint( $eprintid );
        if (defined $eprint)
        {
            next if (!$plugin->can_process( $eprint ));
            
            $query = $plugin->create_query( $eprint );

            if ($plugin->{sendquery})
            {
            	$query_count++;
            	my $ret = $plugin->process_batch();
	
            	# reset query parameters
            	$plugin->{query} = "";
            	$plugin->{querylength} = 0;
            	$plugin->{sendquery} = 0;
            	$plugin->{queryset} = [];
            	
            	# if there is a carry forward, because the query terms didn't find enough space,
            	# carry them over to next round
            	if ($plugin->{carryforward})
            	{
            		$plugin->{carryforward} = 0;
            		$query = $plugin->create_query( $eprint );
            	}
            }
        }
    }
    
    # process the remaining batch
    if ($plugin->{querylength} > 0)
    {
    	$query_count++;
        my $ret = $plugin->process_batch();
    }
    
    # create citation data objects
    foreach my $citedata (sort {$a->{referent_id} <=> $b->{referent_id}} @{$plugin->{citedata}})
    {
		my $dataobj = $plugin->epdata_to_dataobj( $opts{dataset}, $citedata );
		if ( defined $dataobj )
		{
			my $id = $dataobj->get_id;
			push @ids, $id;
			print STDOUT "Updating eprint " . $citedata->{referent_id} . ", WoS UT " . $citedata->{cluster} . 
					", WoS impact " . $citedata->{impact} . "\n";
		}
    }
    
    print STDOUT "Updated " . scalar(@ids) . " out of " . $total . " eprints.\n";
    print STDOUT "$query_count queries used.\n";
    
	return @ids;
}


#
# Check which items the plug-in is able to process 
#
sub can_process
{
	my ($plugin, $eprint) = @_;
	
	my $types = $plugin->{types};
	my $doifield = $plugin->{doifield};
	my $pmidfield = $plugin->{pmidfield};

	if ($eprint->is_set( "wos_cluster" ))
	{
		# do not process eprints with WoS id set to "-"
		return 0 if ($eprint->get_value( "wos_cluster" ) eq "-");

		# otherwise, we can use the existing UT to retrieve data
		return 1;
	}
	
	if ($eprint->is_set( "woslamr_cluster" ))
	{
		# do not process eprints with WoS id set to "-"
		return 0 if ($eprint->get_value( "woslamr_cluster" ) eq "-");

		# otherwise, we can use the existing UT to retrieve data
		return 1;
	}
	
	# Web of Science doesn't contain data for some document types
	my $type = $eprint->get_value( "type" );
	
	return 0 if (!defined $types->{$type});

	# Check if the following query data are available
	return 1 if ($eprint->is_set( $doifield ));
	return 1 if ($eprint->is_set( $pmidfield ));
	return 1 if ($eprint->is_set( "isbn" ));
	return 1 if ($eprint->is_set( "title" ));
	
	return 0;
}

#
# Create a bundled query
#
sub create_query
{
	my ($plugin, $eprint) = @_;
	
	my $query;
	my $querylength = 0;
	
	my $doifield = $plugin->{doifield};
	my $pmidfield = $plugin->{pmidfield};
	
	my $queryfields = $plugin->{queryfields};
	my $queryset = $plugin->{queryset};
	my $eprintid = $eprint->id;

	push @{$queryset}, $eprintid;
	
	my $ut;
	if ($eprint->exists_and_set( "wos_cluster" ))
	{
		$ut = $eprint->get_value( "wos_cluster" );
	}
	if (!defined $ut && $eprint->exists_and_set( "woslamr_cluster" ))
	{
		$ut = $eprint->get_value( "woslamr_cluster" );
	}
	
	if (defined $ut)
	{
		$query = "UT=" . $ut;
		$querylength = 1;
		$plugin->{matchrules}->{$eprintid}->{uid} = $ut;
	}
	else
	{
		if ($eprint->exists_and_set( $doifield ))
		{
			my $doi = $eprint->get_value( $doifield );
			$query = "DO=\"" . $doi . "\"";
			$querylength = 1;
			$plugin->{matchrules}->{$eprintid}->{doi} = $doi;
		}
		elsif ($eprint->exists_and_set( $pmidfield ))
		{
			my $pubmedid = $eprint->get_value( $pmidfield );
			$query = "PMID=" . $pubmedid;
			$querylength = 1;
			$plugin->{matchrules}->{$eprintid}->{pmid} = $pubmedid;
		}
		elsif ($eprint->exists_and_set( "isbn" ))
		{
			my $isbn = $eprint->get_value( "isbn" );
			$isbn =~ s/^\s+|\s+$//;
			my @tmpisbn = split( /[\s,;]/, $isbn );
			$isbn = $tmpisbn[0];
			$query = "IS=" . $isbn ;
			$querylength = 1;
			$plugin->{matchrules}->{$eprintid}->{isbn} = $isbn;
		}
		else
		{
			$query = "(";
			foreach my $qf (keys %{$queryfields})
			{
				if ($eprint->exists_and_set( $qf ))
				{
					$querylength++;
					$query = $query . " AND " if ($querylength > 1);
					my $query_value = $eprint->get_value( $qf );
					
					if ($qf eq "publication" || $qf eq "series")
					{
						if ($query_value =~ /(.*?)=(.*)/)
						{
							$query_value = $1;
						}
					}
					
					# strip unwanted characters
					$query_value =~ s/=//g;
					$query_value =~ s/\x22//g;
					$query_value =~ s/\x24//g;
					$query_value =~ s/\x28//g;
					$query_value =~ s/\x29//g;
					$query_value =~ s/\x2A//g;
					$query_value =~ s/\x3F//g;
					$query_value =~ s/\xAB//g;
					$query_value =~ s/\xBB//g;
					$query_value =~ s/\x{2019}//g;
					$query_value =~ s/\x{201D}//g;
					$query_value =~ s/\x{201E}//g;
					$query_value =~ s/\x{201C}//g;
					
					# replace unwanted characters
					$query_value =~ s/\x23/ /g;
					$query_value =~ s/\x2F/ /g;
					$query_value =~ s/\x40/ /g;
					
					# quote conflicting Boolean and proximity operators
					$query_value =~ s/^AND\s|\sAND\s|\sAND$/ "AND" /gi;
					$query_value =~ s/^OR\s|\sOR\s|\sOR$/ "OR" /gi;
					$query_value =~ s/^NOT\s|\sNOT\s|\sNOT$/ "NOT" /gi;
					$query_value =~ s/^NEAR\s|\sNEAR\s|\sNEAR$/ "NEAR" /gi;
					$query_value =~ s/^SAME\s|\sSAME\s|\sSAME$/ "SAME" /gi;
					
					# strip leading and ending spaces
					$query_value =~ s/^\s+|\s+$//g;
					
					
					if ($query_value =~ /\s/)
					{
						$query .= $queryfields->{$qf} . "=(" .  $query_value . ")";
					}
					elsif ($query_value eq '')
					{
						# skip empty query
					}
					else
					{
						$query .= $queryfields->{$qf} . "=" . $query_value;
					}
					if ($qf eq 'title')
					{
						$plugin->{matchrules}->{$eprintid}->{title} = $query_value;
					}
				}
			}
			
			if ($eprint->exists_and_set( "date" ))
			{
				$querylength++;
				$query = $query . " AND " if ($querylength > 1);
				my $date = $eprint->get_value( "date" );
				my $py = substr( $date, 0, 4 );
				$query .= "PY=" . $py;
			}
			
			if ($eprint->exists_and_set( "pagerange" ))
			{
				my $pagerange = $eprint->get_value( "pagerange" );
				if ($pagerange =~ /\s*(\d*)\s*-.*/)
				{
					my $startpage = $1;
					if ($startpage ne '')
					{
						$querylength++;
						$query .= " AND " if ($querylength > 1);
						$query .= "PG=" . $startpage;
					}
				}
			}
			$query .= ")";
		}
	}
	
	if (($plugin->{querylength} + $querylength) > $plugin->{requestsize})
	{
		$plugin->{carryforward} = 1;
		$plugin->{sendquery} = 1;
	}
	else
	{
		$plugin->{query} .= " OR " if ($plugin->{querylength} > 0);
		$plugin->{querylength} += $querylength;
		$plugin->{query} .= $query;
		$plugin->{sendquery} = 1 if ($plugin->{querylength} == $plugin->{requestsize});
	}
	
	return $plugin->{query};
}

#
# Process a batch of eprints
#
sub process_batch
{
	my ($plugin) = @_;
	
	my $success = 0;
    my $response = $plugin->send_wos_query();
    my $rc = $response->code;
    my $content = $response->decoded_content();
	my $json_response = decode_json( $content );
				
	if ($rc == HTTP_OK)
    {
		# process response
		$success = $plugin->parse_wos_response( $json_response );
    }
    else
    {
		$plugin->handle_wos_error( $json_response, $rc );
    }
    
    return $success;
}

#
# Send the query to the WoS API 
#
sub send_wos_query
{
	my ($plugin) = @_;
	
	my $response;
	
	my $query = $plugin->{query};
	
	my $ua = LWP::UserAgent->new( conn_cache => $plugin->{conn_cache} );
	$ua->env_proxy;
	$ua->default_header( 
		'X-ApiKey' => $plugin->{apikey},
		'Accept' => 'application/json'
	);
	$ua->agent( "ZORA Sync; EPrints 3.3.x; www.zora.uzh.ch" );
	
	my $net_tries_left = $plugin->{net_retry}->{max};
	my $retry_delay = $plugin->{net_retry}->{interval};
	
	# max 5 requests per sec so sleep for 210ms.
	select( undef, undef, undef, 0.21 );
	
	my $uri = $plugin->_get_query_uri( $query );
	$plugin->{quri} = $uri;
	
	while( !defined $response && $net_tries_left > 0 )
	{
		$response = $ua->get( $uri );
		my $rc = $response->code;

		if (!$response->is_success && ($rc == HTTP_INTERNAL_SERVER_ERROR || $rc == HTTP_SERVICE_UNAVAILABLE))
		{
			# no response; go to sleep before trying again
			$plugin->warning(
				'Unable to retrieve data from WoS. The response was: ' . $response->status_line . "Waiting " . $retry_delay .
				" seconds before trying again."
			);
			sleep( $retry_delay );
			$net_tries_left--;
		}
	}
	
	return $response;
}

#
# Construct the query URI for the WoS Starter API
#
sub _get_query_uri
{
	my ($plugin, $query) = @_;
	
	my $baseurl = URI->new( $plugin->{apiurl} );
	my $quri = $baseurl->clone;
	
	$quri->query_form(
		db => 'WOS',
		q => $query,
		limit => $plugin->{requestsize},
		page => 1,
		sortField => "LD+A",
	);
	
	return $quri;
}

#
# Parse the WoS response and assign the results to the correct eprint
#
sub parse_wos_response
{
	my ($plugin, $wos_response) = @_;
	
	my $parsesuccess = 0;
	
	return $parsesuccess if (!defined $wos_response->{hits});
	
	foreach my $eprintid (keys %{$plugin->{matchrules}})
	{
		foreach my $matchfield (keys %{$plugin->{matchrules}->{$eprintid}})
		{
			my $matchvalue = $plugin->{matchrules}->{$eprintid}->{$matchfield};
			my $matchcompare = $matchvalue;
			
			if ($matchfield eq 'uid')
			{
				$matchcompare = "WOS:" . $matchvalue;
			}
			
			if ($matchfield eq 'title')
			{
				$matchcompare = lc( $matchcompare );
				$matchcompare =~ s/[[:punct:]]//g;
			}
			
			my $match = 0;
			foreach my $hit (@{$wos_response->{hits}})
			{
				last if $match;
				if ($matchfield eq 'uid')
				{
					if ($hit->{uid} eq $matchcompare)
					{
						$match = 1;
						my $ret = $plugin->_store_wos_citedata( $hit, $eprintid );
					}
				}
				
				if ($matchfield eq 'doi')
				{
					my $wos_doi = $hit->{identifiers}->{doi};
					if (defined $wos_doi && $wos_doi eq $matchcompare)
					{
						$match = 1;
						my $ret = $plugin->_store_wos_citedata( $hit, $eprintid );
					}
				}
				
				if ($matchfield eq 'pmid')
				{
					my $wos_pmid = $hit->{identifiers}->{pmid};
					if (defined $wos_pmid && $wos_pmid eq $matchcompare)
					{
						$match = 1;
						my $ret = $plugin->_store_wos_citedata( $hit, $eprintid );
					}
				}
				
				if ($matchfield eq 'isbn')
				{
					my $isbn;
					if (defined $hit->{identifiers}->{isbn})
					{
						$isbn = $hit->{identifiers}->{isbn};
					}
					if (defined $hit->{identifiers}->{eisbn})
					{
						$isbn = $hit->{identifiers}->{eisbn};
					}
					
					if (defined $isbn && $isbn eq $matchcompare)
					{
						$match = 1;
						my $ret = $plugin->_store_wos_citedata( $hit, $eprintid );
					}
				}
				
				if ($matchfield eq 'title')
				{
					my $title = lc( $hit->{title} );
					$title =~ s/[[:punct:]]//g;
					
					if ($title eq $matchcompare)
					{
						$match = 1;
						my $ret = $plugin->_store_wos_citedata( $hit, $eprintid );
					}
				}
			}
		}
	}
	
	$parsesuccess = scalar( @{$plugin->{citedata}} );
	
	return $parsesuccess;
}



#
# Store WoS citation counts in citedata hash
#
sub _store_wos_citedata
{
	my ($plugin, $hit, $eprintid) = @_;
	
	my $uid = $hit->{uid};
	$uid =~ s/^WOS://;
	
	my $citation_count = 0;
	foreach my $citation (@{$hit->{citations}})
	{
		if ($citation->{db} eq 'WOS')
		{
			$citation_count = $citation->{count};
		}
	}
				 
	push @{$plugin->{citedata}}, {
		referent_id => $eprintid,
		cluster => $uid,
		impact => $citation_count,
		datestamp => EPrints::Time::get_iso_timestamp(),
	};
	
	return 1;
}

#
#  Print errors resulting from WoS API
#
sub handle_wos_error
{
	my ($plugin, $json_response, $rcode) = @_;
		
	print STDERR "WoS Query: " . $plugin->{quri} . "\n";
	if ($rcode != HTTP_UNAUTHORIZED)
	{
		print STDERR "WoS API HTTP Status: " . $json_response->{error}->{status} . "\n";
		print STDERR "WoS API Error: " . $json_response->{error}->{title} . "\n";
		print STDERR "WoS API Error Details: " . $json_response->{error}->{details} . "\n";
	}
	else
	{
		print STDERR "WoS API HTTP Status: $rcode\n";
		print STDERR "WoS API Error: " . $json_response->{error} . "\n";
		print STDERR "WoS API Error Description: " . $json_response->{error_description} . "\n";
	}
	
	return;
}

1;
