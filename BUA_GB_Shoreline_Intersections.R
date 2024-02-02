###########################################################
### IDENTIFY BUILT UP AREAS THAT INTERSECT GB SHORELINE ###
###########################################################

# Required libraries
library(sf) # version 1.0.12 used
library(dplyr) # version 1.1.2 used
library(geos) # version 0.2.2 used
library(writexl) # version 1.4.2 used

# Read in input data
OS_Grid_10k_Tiles_UK <- st_read("[ADD_DATA_LOCATION_HERE]")
BUAs <- st_read("[ADD_DATA_LOCATION_HERE]")
GB_Shoreline <- st_read("[ADD_DATA_LOCATION_HERE]")

# Set to 'False' as input data uses a projected coordinate system (rather than a geographic coordinate system)
### Why? This is to prevent possible longer computation time that using s2 (rather than GEOS) can cause
sf_use_s2(FALSE)

# Specify buffer size in metres to be used
### Why? As Built Up Areas are made of 25m grid cells they will not align perfectly with the GB Shoreline.
### The buffer is used to make the shoreline wider, enabling more consistent and realistic intersections with Built Up Areas
Buffer_Size <- 50

# Cast 'GB_Shoreline' from multipolygon object to individual polygons and calculate each polygon's area
GB_Shoreline_with_Area <- GB_Shoreline %>%
	st_cast("POLYGON") %>%
	mutate(Area_m2 = as.numeric(st_area(.)))

# Buffer 'GB_Shoreline_with_Area' features by 'Buffer_Size' if they have areas less than what the minimum area of a feature buffered by the 'Buffer_Size' value would have
### Why? 'geos_buffer' and 'st_buffer' both struggle to buffer polyline features that are smaller than the minimum area of a possible buffer
GB_Shoreline_Polygon_Buffer <- GB_Shoreline_with_Area %>%
	filter(Area_m2 < pi*((Buffer_Size+1)^2)) %>%
	geos_buffer(., Buffer_Size) 

# Filter 'GB_Shoreline_with_Area' features that have areas greater than the minimum area possible when buffered by the 'Buffer_Size', merge together and cast as polyline
paste0("Stated: ", Sys.time(), " - takes 2 minutes")
GB_Shoreline_Polyline_Filter <- GB_Shoreline_with_Area %>%
	filter(Area_m2 >= pi*((Buffer_Size+1)^2)) %>%
	st_union(.) %>%
	st_cast(.,"MULTILINESTRING")	

# Intersect 'GB_Shoreline_Polyline_Filter' with 'OS_Grid_10k_Tiles_UK'
### Why? This speeds up the next process (buffering). Rather than buffer one very complex polyline it buffers multiple simpler polylines
paste0("Stated: ", Sys.time(), " - takes 6 minutes")
GB_Shoreline_Polyline_10k_Tiles <- GB_Shoreline_Polyline_Filter %>%
	st_intersection(., OS_Grid_10k_Tiles_UK) 

# Buffer 'GB_Shoreline_Polyline_10k_Tiles' features by 'Buffer_Size'
paste0("Stated: ", Sys.time(), " - takes 8 minutes")
GB_Shoreline_Polyline_Buffer <- GB_Shoreline_Polyline_10k_Tiles %>%
	geos_buffer(.,Buffer_Size) 

# Join 'GB_Shoreline_Polyline_Buffer' and 'GB_Shoreline_Polygon_Buffer' to create single buffered polygon of GB Shoreline
paste0("Stated: ", Sys.time(), " - takes 5 minutes")
GB_Shoreline_Buffer <- bind_rows(
		GB_Shoreline_Polyline_Buffer %>% st_as_sfc(.) %>% st_sf(), 
		GB_Shoreline_Polygon_Buffer %>% st_as_sfc(.) %>% st_sf()) %>%
	geos_make_collection() %>% 
	geos_unary_union() %>%
	st_as_sfc(.)

# Cast 'GB_Shoreline_Buffer' from multipolygon object to individual polygons and intersect with 'OS_Grid_10k_Tiles_UK'
### Why? This speeds up the next process (intersection). Rather than intersect one very complex polyline it intersects multiple simpler polylines
paste0("Stated: ", Sys.time(), " - takes 45 minutes")
GB_Shoreline_Buffer_Polygon <- GB_Shoreline_Buffer %>%
	st_cast("POLYGON") %>%
	st_intersection(., OS_Grid_10k_Tiles_UK) 

# Convert 'BUAs' to be a polyline 
BUA_Polylines <- BUAs %>%
	st_cast(.,"MULTILINESTRING") %>%
	mutate(BUA_Perimeter_KM = as.numeric(st_length(.)/ 1000))

# Merge BUAs that touch into single features, cast this output as single polygons and covert to polylines
# Intersect this output with 'GB_Shoreline_Buffer_Polygon' to select only the parts of polylines that intersect with the shoreline
### Why? Merging touching BUAs avoids any small parts of shared BUA borders being incorrectly identified as being on the shoreline due when intersected 
paste0("Stated: ", Sys.time(), " - takes 5 minutes")
BUA_Union_Shoreline_Intersection <- BUAs %>%
	summarise(geometry = st_union(geom)) %>%
	st_cast(.,"POLYGON") %>%
	st_cast(.,"MULTILINESTRING") %>%
	st_intersection(., GB_Shoreline_Buffer_Polygon) %>%
	st_collection_extract(., "LINESTRING") 

# Intersect 'BUA_Polylines' with 'BUA_Union_Shoreline_Intersection' to assign the shoreline polylines to BUAs. Then create a number of summary statistics
BUA_Shorelines <- BUA_Polylines %>%
	st_intersection(., BUA_Union_Shoreline_Intersection) %>%
	mutate(BUA_Shoreline_KM = as.numeric(st_length(.)/ 1000)) %>%
	group_by(BUA22CD, BUA22NM, BUA22NMW, BUA22NMG, BNG_E, BNG_N, LONG, LAT) %>%
	summarise(BUA_Perimeter_KM = max(BUA_Perimeter_KM),
			BUA_Shoreline_KM = sum(BUA_Shoreline_KM)) %>%
	mutate(BUA_Shoreline_PCT = (BUA_Shoreline_KM/BUA_Perimeter_KM)*100) %>%
	relocate(BUA_Shoreline_PCT, .after = BUA_Shoreline_KM) %>%
	arrange(BUA22CD) %>%
	st_sf()

# Subtract 'BUA_Shorelines' from 'BUA_Polylines' to generate polylines for the inland component of BUAs. Then create a number of summary statistics
paste0("Stated: ", Sys.time(), " - takes 1 hour 15 minutes")
BUA_Inland <- BUA_Polylines %>%
	st_difference(., st_union(BUA_Shorelines)) %>%
	mutate(BUA_Inland_KM = as.numeric(st_length(.)/ 1000)) %>%
	group_by(BUA22CD, BUA22NM, BUA22NMW, BUA22NMG, BNG_E, BNG_N, LONG, LAT) %>%
	summarise(BUA_Perimeter_KM = max(BUA_Perimeter_KM),
			BUA_Inland_KM = sum(BUA_Inland_KM)) %>%
	mutate(BUA_Inland_PCT = (BUA_Inland_KM/BUA_Perimeter_KM)*100)%>%
	relocate(BUA_Inland_PCT, .after = BUA_Inland_KM) %>%
	arrange(BUA22CD) %>%
	st_sf()

# Create a table of 'BUA_Shorelines'
BUA_Shorelines_Table <- BUA_Shorelines %>%
	st_drop_geometry() %>%
	arrange(BUA22CD)

# Create a table of 'BUA_Inland'
BUA_Inland_Table <- BUA_Inland %>%
	st_drop_geometry()%>%
	arrange(BUA22CD)	

# Create Excel sheets						
Excel_WB <- list("BUAs_Shoreline_Data" = BUA_Shorelines_Table, 
				"BUAs_Inland_Data" = BUA_Inland_Table)
				
# Export Excel workbook
write_xlsx(Excel_WB, "[DIRECTORY_PATH]/BUA_Shoreline_and_Inland_Data_June_2023.xlsx")

# Export polyline outputs
st_write(BUA_Shorelines, paste0("[DIRECTORY_PATH]/BUA_Shoreline_Intersection_Polyline.gpkg"))
st_write(BUA_Inland, paste0("[DIRECTORY_PATH]/BUA_Inland_Intersection_Polyline.gpkg"))

### Outputs in 'BUA_Shorelines_Table'
# 'BUA_Perimeter_KM' is the total perimeter in kilometres of the Built Up Area
# 'BUA_Shoreline_KM' is length of each Built Up Area's perimeter that intersects the GB shoreline
# 'BUA_Shoreline_PCT' is the percentage of how much each Built Up Area's perimeter intersects the GB shoreline

### Outputs in 'BUA_Inland_Table'
# 'BUA_Perimeter_KM' is the total perimeter in kilometres of the Built Up Area
# 'BUA_Inland_KM' is length of each Built Up Area's perimeter that is inland and does not intersect the GB shoreline
# 'BUA_Inland_PCT' is the percentage of how much each Built Up Area's perimeter is inland and does not intersect the GB shoreline
