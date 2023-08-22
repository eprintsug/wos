######################################################################
#
#  Configuration for Web of Science citation ingest.
#
#  This plug-in retrieves citation data from the WoS Starter API.
#  It is called by Queensland University of Technology Citation Count 
#  Dataset and Import plug-ins for EPrints 3.
#
#  Part of https://idbugs.uzh.ch/browse/ZORA-1061
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
######################################################################

# WoS Starter API base URL
$c->{plugins}->{"Import::CitationService::WoS"}->{params}->{baseurl} = "https://api.clarivate.com/apis/wos-starter/v1/documents";

# WoS Starter API Key
$c->{plugins}->{"Import::CitationService::WoS"}->{params}->{apikey} = "{insert your API key here}";

# Request size (maximum number of terms per query, maximum allowed is 50)
$c->{plugins}->{"Import::CitationService::WoS"}->{params}->{requestsize} = 50;

# Maximum requests per day
$c->{plugins}->{"Import::CitationService::WoS"}->{params}->{maxrequests} = 5000;

# Allowed document types  (please configure according to your repository)
$c->{plugins}->{"Import::CitationService::WoS"}->{params}->{types} = {
	"article" => 1,
	"book_section" => 1,
	"conference_item" => 1,
	"monograph" => 1,
	"edited_scientific_work" => 1,
};

# Field name of DOI field (please configure according to your repository)
$c->{plugins}->{"Import::CitationService::WoS"}->{params}->{doifieldname} = "doi";

# Field name of PMID field (please configure according to your repository)
$c->{plugins}->{"Import::CitationService::WoS"}->{params}->{pmidfieldname} = "pubmedid";

# Mapping of EPrints fields to WoS query fields (please configure according to your repository)
$c->{plugins}->{"Import::CitationService::WoS"}->{params}->{queryfields} = {
	"title" => "TI", 
	"publication" => "SO", 
	"series" => "SO", 
	"issn" => "IS",
	"volume" => "VL", 
	"number" => "CS",
};
