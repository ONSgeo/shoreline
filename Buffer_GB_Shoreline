###########################
### BUFFER GB SHORELINE ###
###########################

### You can use this code to buffer the GB Shoreline by any amount. 
### The smaller the buffer the longer it will take to run.
### Takes 30 minutes to do 500 metre buffer and 10 minutes to do 5km buffer on Intel Core i5-6500T @ 2.50GHz with 32GB RAM

# Required libraries
library(sf) # version 1.0.12 used
library(dplyr) # version 1.1.2 used
library(geos) # version 0.2.2 used

# Read in input data
OS_Grid_10k_Tiles_UK <- st_read("[ADD_DATA_LOCATION_HERE]")
GB_Shoreline <- st_read("[ADD_DATA_LOCATION_HERE]")

# Select buffer size in metres
Buffer_Size <- 5000

# Convert buffer size to kilometres
Buffer_Size_KM <- Buffer_Size/1000

Start <- Sys.time()

# Cast 'GB_Shoreline' from multipolygon object to individual polygons and calculate each polygon's area
GB_Shoreline_with_Area <- GB_Shoreline %>%
	st_cast("POLYGON") %>%
	mutate(Area_m2 = as.numeric(st_area(.)))

# Buffer 'GB_Shoreline_with_Area' features by 'Buffer_Size' if they have areas less than what the minimum area of a feature buffered by the 'Buffer_Size' value would have
### Why? 'geos_buffer' and 'st_buffer' both struggle to buffer polyline features that are smaller than the minimum area of a possible buffer
paste0("Time taken so far: ", round(difftime(Sys.time(), Start, units='mins'),2)," minutes")
GB_Shoreline_Polygon_Buffer <- GB_Shoreline_with_Area %>%
	filter(Area_m2 < pi*((Buffer_Size+1)^2)) %>%
	geos_buffer(., Buffer_Size) 

# Filter 'GB_Shoreline_with_Area' features that have areas greater than the minimum area possible when buffered by the 'Buffer_Size', merge together and cast as polyline
paste0("Time taken so far: ", round(difftime(Sys.time(), Start, units='mins'),2)," minutes")	
GB_Shoreline_Polyline_Filter <- GB_Shoreline_with_Area %>%
	filter(Area_m2 >= pi*((Buffer_Size+1)^2)) %>%
	st_union(.) %>%
	st_cast(.,"MULTILINESTRING")	

# Intersect 'GB_Shoreline_Polyline_Filter' with 'OS_Grid_10k_Tiles_UK'
### Why? This speeds up the next process (buffering). Rather than buffer one very complex polyline it buffers multiple simpler polylines
paste0("Time taken so far: ", round(difftime(Sys.time(), Start, units='mins'),2)," minutes")
GB_Shoreline_Polyline_10k_Tiles <- GB_Shoreline_Polyline_Filter %>%
	st_intersection(., OS_Grid_10k_Tiles_UK) 

# Buffer 'GB_Shoreline_Polyline_10k_Tiles' features by 'Buffer_Size'
paste0("Time taken so far: ", round(difftime(Sys.time(), Start, units='mins'),2)," minutes")
GB_Shoreline_Polyline_Buffer <- GB_Shoreline_Polyline_10k_Tiles %>%
	geos_buffer(.,Buffer_Size) 

# Join 'GB_Shoreline_Polyline_Buffer' and 'GB_Shoreline_Polygon_Buffer' to create single buffered polygon of GB Shoreline
paste0("Time taken so far: ", round(difftime(Sys.time(), Start, units='mins'),2)," minutes")
GB_Shoreline_Buffer <- bind_rows(GB_Shoreline_Polyline_Buffer %>% st_as_sfc(.) %>%  st_sf(), 
		GB_Shoreline_Polygon_Buffer %>% st_as_sfc(.) %>% st_sf()) %>%
	geos_make_collection() %>% 
	geos_unary_union() %>%
	st_as_sfc(.)

paste0("Time taken to finish: ", round(difftime(Sys.time(), Start, units='mins'),2)," minutes")

# Export outputs
st_write(GB_Shoreline_Buffer, paste0("[DIRECTORY_PATH]/GB_Shoreline_June_2023_",Buffer_Size_KM,"km_Buffer.gpkg"))
