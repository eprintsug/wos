# Web of Science citation plugin (WoS REST API based)

## Description
This plug-in retrieves citation data from the WoS Starter API.
It is called by the Queensland University of Technology Citation Count 
Dataset and Import plug-ins for EPrints 3.

It replaces the deprecated WoS citation plug-ins that are based on the WoS
LAMR and WoS SOAP based interfaces.

## Prerequisites
Installation of QUT Technology Citation Count Dataset and Import plug-ins for EPrints 3 is required,
see either [citation-import on eprintsug](https://github.com/eprintsug/citation-import) or [citation-import on EPrints files](http://files.eprints.org/815/).

## Installation
Deactivate {eprints_root}/perl_lib/EPrints/Plugin/Import/CitationService/WoS.pm by renaming it.

Copy Plugin/Import/CitationService/WoS.pm either to {eprints_root}/archives/{repo}/cfg/plugins/EPrints/Plugin/Import/CitationService/WoS.pm or to {eprints_root}/perl_lib/EPrints/Plugin/Import/CitationService/WoS.pm 

Copy cfg.d/z_wos.pl to {eprints_root}/archives/{repo}/cfg/cfg.d/z_wos.pl

Edit {eprints_root}/archives/{repo}/cfg/cfg.d/z_wos.pl and insert/modify all the necessary data 
(API key from Clarivate, field definitions)

### Edit your cron table

Create a shell script that calls bin/update_citationdata {repository_name} wos
Depending on your environment, you may also need to specify a http/https proxy server.
Add this script to your crontab; we recommend to carry out the update job daily.

### Rendering the citation data

Rendering of the citation data is highly specific to how the repository was configured.
You can add the WoS fields to your cfg/citations/eprint/summary_page.xml. Others (as we
do at UZH) use a tailored cfg.d/eprint_render.pl to render the summary page. We provide
a snippet in cfg.d/eprint_render_snippet.pl that you can take as an example for your repo.
If you take this example, please replace the placeholder {repository-appname} with the app 
name provided by Clarivate upon the API key registration.
