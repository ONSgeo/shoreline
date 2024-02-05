# ONS GB Shoreline and related work

### This page contains an outline of how ONS Geospatial has:
*	Defined and created a GB shoreline
*	Buffered GB shoreline
*	Identified Built Up Areas (2022) that intersect GB shoreline

## Code language
*	R 

## Input data
*	1 kilometre OS Grid Tiles for Great Britain
*	10 kilometre OS Grid Tiles for Great Britain
*	2022 Built Up Areas
*	Great Britain country boundaries (full resolution extent of the realm/low water mark)
*	Great Britain country boundaries (full resolution clipped to the coastline/high water mark)
*	‘Water’ from OS Select+Build
*	‘Land’ from OS Select+Build

## Where to get the input data from
*	1 kilometre and 10 kilometre OS Grid Tiles for Great Britain can be downloaded from: https://github.com/OrdnanceSurvey/OS-British-National-Grids. Alternatively, they can be created in R using the code from this StackOverflow question: https://stackoverflow.com/questions/62169741/add-os-national-grid-names-codes-to-grid-in-r 
*	2022 Built Up Areas can either be downloaded from the OS Data Hub (https://osdatahub.os.uk/downloads/open/BuiltUpAreas) or from ONS’ Open Geography Portal (https://geoportal.statistics.gov.uk/datasets/ons::built-up-areas-2022-gb-bgg/about). Note: the polygons are the same in either version, but the attribution has different formatting.
*	Great Britain country boundaries can be downloaded from the ONS’ Open Geography Portal. Full resolution extent of the realm: https://geoportal.statistics.gov.uk/datasets/ons::countries-december-2022-boundaries-gb-bfe/about and full resolution clipped to the coastline: https://geoportal.statistics.gov.uk/datasets/ons::countries-december-2022-boundaries-uk-bfc/about 
*	‘Water’ from OS Select+Build can be accessed if you have an OS Data Hub account (under the 'Downloads' section) and are a PSGA member by: OS Select+Build > Create a new recipe > give the data package a name and from ‘Themes’ select Water → Water Features → Water > Create recipe. On the next page Click ‘ Add data package’ under the data package just created and give the package a name, select ‘British National Grid’ as the Coordinate Reference System, GeoPackage as the file format, select the first of the current month as the initial supply date and select how often (if at all) you’d like this package updated. Click ‘Create data package’ and download file once ready. NOTE - This produces a fairly large download file (about 1GB).
*	‘Land’ can be downloaded from OS Select+Build using the same instructions as above, expect when creating a new recipe the ‘Themes’ to select are Land → Land Features → Land.  NOTE - This produces a very large download file (about 20GB).

## Define and create GB shoreline outline
*	The ONS GB Shoreline is created by taking full resolution extent of the realm boundaries (also known as low water mark) and ‘cookie-cutting’ out selective areas of sea, tidal water and tidal land taken from Ordnance Survey data.
*	The areas selected for ‘cookie-cutting’ broadly fall into four categories:
    -	Assigned as Sea in ‘Water’ from OS Select+Build (e.g. the area between low and high water marks)
    -	Assigned as i) tidal water in ‘Water’ from OS Select+Build, ii) intersect with the Built Up Areas 2022 geography and iii) can be considered to be near the sea (e.g. the tidal water around Southampton is considered to be near the sea, the tidal River Ribble going through Preston is not)
    -	Assigned as i) tidal water in ‘Water’ from OS Select+Build, ii) does not intersect with the Built Up Areas 2022 geography but iii) can be considered a substantial water body (e.g. Christchurch Harbour is considered to be substantial, but a tidal river like the Beaulieu River in Hampshire is not)
    -	Assigned as tidal land in ‘Land’ from OS Select+Build and touch selected tidal water features
*	The areas of sea, tidal water and tidal land that are used for the ‘cookie-cutting’ are selected using an automated process run in R. The commented code explains the process step-by-step. It also includes commentary as to why certain steps were necessary and how certain areas were included/excluded.

## Buffer GB shoreline
* Due to the complexities of the GB shoreline geometry, running a simple buffer (e.g. `geos_buffer` or `st_buffer` in R) on the whole dataset can take a long time to complete.
* Instead of buffering the entire dataset, it is chunked by 10km OS grid tiles. So rather than buffering one very complex polyline it buffers multiple simpler polylines.
* A polyline version of the shoreline is used for the majority of the buffering. However, the polygon version is used for objects smaller than the minimum size of the buffer. This is because `geos_buffer` and `st_buffer` both struggle to buffer polyline features that are smaller than the minimum area of a possible buffer.

## Identify Built Up Areas (2022) that intersect GB shoreline
*	As Built Up Areas are constructed from 25 metre grid squares, edges that would be considered touching the shoreline do not always intersect with it.
*	As such, a buffer is used to make the shoreline wider, enabling more consistent and realistic intersections with Built Up Areas.
*	This allows the following outputs to be created for all Built Up Areas that touch the GB shoreline:
    - 'BUA_Perimeter_KM' is the total perimeter in kilometres of the Built Up Area
    - 'BUA_Shoreline_KM' is length of each Built Up Area's perimeter that intersects the GB shoreline
    - 'BUA_Shoreline_PCT' is the percentage of how much each Built Up Area's perimeter intersects the GB shoreline

