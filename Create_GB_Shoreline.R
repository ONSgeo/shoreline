#############################
### CREATE A GB SHORELINE ###
#############################

# Required libraries
library(sf) # version 1.0.12 used
library(dplyr) # version 1.1.2 used
library(purrr) # version 1.0.1 used
library(stringr) # version 1.5.0 used

# Read in input data 
OS_Grid_1km_Tiles_UK <- st_read("[ADD_DATA_LOCATION_HERE]")
GB_BFE <- st_read("[ADD_DATA_LOCATION_HERE]") # Loads in country data (full resolution extent of the realm, i.e., low water mark)
GB_BFC <- st_read("[ADD_DATA_LOCATION_HERE]") # Loads in country data (clipped to the coastline, i.e., high water mark)
BUAs <- st_read("[ADD_DATA_LOCATION_HERE]") # Loads in Built Up Areas data
Water <- st_read("[ADD_DATA_LOCATION_HERE]") # Loads in water data
Land_Tidal <- st_read(dsn = paste0("[ADD_DATA_LOCATION_HERE]"),
                  query = "select * from lnd_fts_land_tidal where istidal = TRUE") # Loads in land dataset, filtered to tidal
 
# Enter the month and year of the Ordnance Survey data (Water and Land_Tidal) used
OS_Data_Month_Year <- "June_2023"

# Rename some field names to ensure consistency regardless of differing versions of input data
colnames(OS_Grid_1km_Tiles_UK)[which(colnames(OS_Grid_1km_Tiles_UK) =="[ADD_NAME_OF_GRID_REF_FIELD_HERE ]")] <- “OS_Grid_Reference”
 
Start_Time <- Sys.time() 
Start_Time

# Filter 'Water' so it only contains sea and tidal attributes
Water_Subset <- Water %>% filter(description == "Sea" | watertype == "Tidal")

# Remove 'Water' object as no longer needed
rm(Water)

# Standardise the naming of the geometry column in loaded sf objects
st_geometry(OS_Grid_1km_Tiles_UK) <- "geometry"
st_geometry(BUAs) <- "geometry"
st_geometry(GB_BFE) <- "geometry"
st_geometry(GB_BFC) <- "geometry"
st_geometry(Water_Subset) <- "geometry"
st_geometry(Land_Tidal) <- "geometry"

# Fix error in data (this was fixed in the 1st June 2023 cut of the data but have left the code in case useful in the future)
#Water_Subset <- Water_Subset %>%
#	mutate(description = case_when(str_detect(osid, "3e9b0fe1-965f-4492-9bb4-3441a56e2a0d") ~ 'Sea', TRUE  ~ description))

# Filter so only 1km grid tiles that intersect with BUAs are retained - 1 to 2 minutes to run
ONS_Grid_1km_BUAs <- OS_Grid_1km_Tiles_UK[BUAs,]

# Add field to 'OS_Grid_1km_Tiles_UK' to indicate if that 1km grid cell intersects with a BUA
OS_Grid_1km_Tiles_UK <- OS_Grid_1km_Tiles_UK %>% 
	mutate(BUA_INTERSECT = case_when(
		OS_Grid_Reference %in% ONS_Grid_1km_BUAs$OS_Grid_Reference == TRUE ~ "TRUE",
		TRUE ~ "FALSE")) %>%
	relocate(BUA_INTERSECT, .after = OS_Grid_Reference)

# List of features in 'Water_Subset' that touch by each feature
paste0("Stated: ", Sys.time(), " - takes 10 mintutes")
Touching_Water_Subset_Features_List <- st_touches(Water_Subset, sparse = TRUE)

# Function to return turn list of features that touch each feature into a table
Touching_Water_Subset_DF <- function(idx)  {
  data.frame(Origin_Feature = rep(Water_Subset$osid[idx], length(Touching_Water_Subset_Features_List[[idx]])), 
             Touching_Feature = Water_Subset$osid[Touching_Water_Subset_Features_List[[idx]]])
}

# Table with origin and touching features in 'Water_Subset'
Touching_Water_Subset_Features <- purrr::map_dfr(seq_along(Touching_Water_Subset_Features_List), Touching_Water_Subset_DF) %>%
	left_join(., Water_Subset %>% st_drop_geometry %>% select(osid, description, watertype), join_by(Origin_Feature == osid)) %>%
	rename(Origin_Description = description, Origin_Watertype = watertype) %>%
	left_join(., Water_Subset %>% st_drop_geometry %>% select(osid, description, watertype), join_by(Touching_Feature == osid)) %>%
	rename(Touching_Description = description, Touching_Watertype = watertype) %>%
	as_tibble()

# Join 'Watercourse' features from 'Water_Subset' that touch each other together
### Why? This is so multiple features are joined into single features. 
### This means in later steps, when only features that touch the sea are kept, larger areas of tidal water are retained
paste0("Stated: ", Sys.time(), " - takes 5 minutes")
Watercourse_Union <- Water_Subset %>%
	filter(description == "Watercourse") %>%
	st_union(.) %>%
	st_cast("POLYGON") %>% 
	st_sf() %>%
	mutate(Union_id = paste0("id_",row_number()),
		Union_Area_m2 = as.numeric(st_area(.)))

##### SELECTING WATERCOURSE FEATURES THAT INTERSECT WITH BUAS #####

# Intersect 'Watercourse_Union' features with 1km grid cells that intersect BUAs
### Why? This is to only keep tidal water features that fall within 1km grid cells that intersect with BUAs.
### This is the first step needed to ultimately remove tidal water that goes along way inland and would lead to many inland settlements being classed as being on the shoreline
paste0("Stated: ", Sys.time(), " - takes 5 minutes")
Watercourse_BUA_Intersection <- Watercourse_Union %>%
	st_intersection(., OS_Grid_1km_Tiles_UK) %>%
	st_collection_extract(., "POLYGON") %>%
	filter(BUA_INTERSECT == TRUE) 

# Selects only 1km cells from 'Watercourse_BUA_Intersection' that are touching the sea
### Why? This is so only tidal water features that intersect a BUA and touch the sea are kept
Watercourse_BUA_Intersection_Touching_Sea <- Watercourse_BUA_Intersection %>%
	st_filter(., Water_Subset %>%
		select(osid, description, watertype) %>%
		filter(description == "Sea"), .predicate = st_touches)

# Uses 'Union_id' from the 1km cells in 'Watercourse_BUA_Intersection' that are touching the sea to select the entire feature from 'Watercourse_Union'
### Why? This allows for the entire feature, not just the 1km parts that touch the sea, to be selected
### These selected features intersect a BUA and touch the sea
Watercourse_Union_BUA_Intersection_Touching_Sea <- Watercourse_Union %>%
	filter(Union_id %in% Watercourse_BUA_Intersection_Touching_Sea$Union_id)

##### SELECTING WATERCOURSE FEATURES THAT DO NOT INTERSECT WITH BUAS #####

# This selects all watercourse features not included in 'Watercourse_Union_BUA_Intersection_Touching_Sea'
Watercourse_Union_No_BUA_Intersection <- Watercourse_Union %>%
	filter(!(Union_id %in% Watercourse_BUA_Intersection_Touching_Sea$Union_id))

# This fitlers 'Watercourse_Union_No_BUA_Intersection' so only features that are touching the sea are included
### Why? This allows features that touch the sea, but don't intersect BUAs, to be selected.
### This is the first step in identifying substantial water bodies that don't intersect with BUAs but should be included in the final output
Watercourse_Union_No_BUA_Intersection_Touching_Sea <- Watercourse_Union_No_BUA_Intersection %>% 
	st_filter(., Water_Subset %>%
		select(osid, description, watertype) %>%
		filter(description == "Sea"), .predicate = st_intersects)
		
# This selects features from 'Water_Subset' that intersect with 'Watercourse_Union_No_BUA_Intersection_Touching_Sea'
### Why? Filtering 'Water_Subset' (where features are still separate), rather than the merged polygons in 'Watercourse_Union_No_BUA_Intersection_Touching_Sea' is needed for the next steps
Watercourse_Union_No_BUA_Intersection_Touching_Sea_Features <- Water_Subset %>%
	select(osid, description, watertype) %>%
	filter(description == "Watercourse") %>% 
	st_filter(., Watercourse_Union_No_BUA_Intersection_Touching_Sea, .predicate = st_intersects)

# This creates a list of which features in 'Watercourse_Union_No_BUA_Intersection_Touching_Sea_Features' touch the sea
Touching_Sea_IDs <- Watercourse_Union_No_BUA_Intersection_Touching_Sea_Features	%>% 
	st_filter(., Water_Subset %>% filter(description == "Sea"), .predicate = st_touches) %>%
	select(osid) %>%
	st_drop_geometry() %>%
	unlist %>%
	unique()

# This filters 'Watercourse_Union_No_BUA_Intersection_Touching_Sea_Features' so only the features touching the sea are included
Watercourse_Touching_Sea <- Watercourse_Union_No_BUA_Intersection_Touching_Sea_Features %>%
	filter(osid %in%Touching_Sea_IDs)	

# Filter 'Watercourse_Union_No_BUA_Intersection_Touching_Sea_Features' to select only features that are not directly touching sea 
# These are then negatively buffered by 100 metres and then positively buffered by 100 metres
### Why? This is so narrow channels (most likely rivers) are removed from the dataset, whilst substantial (wider) water bodies remain
Watercourse_Not_Touching_Sea_Buffers <- Watercourse_Union_No_BUA_Intersection_Touching_Sea_Features %>%
	filter(!(osid %in%Touching_Sea_IDs)) %>%
	st_buffer(.,-100, endCapStyle="FLAT") %>%
	st_buffer(.,100, endCapStyle="FLAT") %>%
	filter(!st_is_empty(.))

# List of osid's in 'Watercourse_Not_Touching_Sea_Buffers' that intersect with 'Watercourse_Touching_Sea'
Watercourse_Not_Touching_Sea_Buffers_IDs <-	Watercourse_Not_Touching_Sea_Buffers %>%
	st_filter(., Watercourse_Touching_Sea, .predicate = st_intersects) %>%
	select(osid) %>%
	st_drop_geometry() %>%
	unlist %>%
	unique()

# This selects features from 'Watercourse_Not_Touching_Sea_Buffers' that intersect with 'Watercourse_Touching_Sea' and joins them to 'Watercourse_Touching_Sea'
###Why? This removes smaller water features (like small tributaries) that are connected to features that touch the sea but don't intersect with BUAs 
Watercourse_Connected_to_Sea <- Watercourse_Union_No_BUA_Intersection_Touching_Sea_Features %>%
	filter(osid %in% Watercourse_Not_Touching_Sea_Buffers_IDs) %>%
	bind_rows(., Watercourse_Touching_Sea)

# Join 'Sea' features from 'Water_Subset' to 'Watercourse_Connected_to_Sea'
### Why? This creates a layer of tidal water features that touch the sea, does not contain smaller tidal features and do not intersect BUAs with the sea and joins them to the sea
Watercourse_Connected_to_Sea_and_Sea <- bind_rows(Water_Subset %>% 
	filter(description == "Sea") %>% 
	select(osid, description, watertype), Watercourse_Connected_to_Sea)

# List of features in 'Watercourse_Connected_to_Sea_and_Sea' that touch by each feature
paste0("Stated: ", Sys.time(), " - takes 5 minutes")
Watercourse_Connected_to_Sea_Touching_List <- st_touches(Watercourse_Connected_to_Sea_and_Sea, sparse = TRUE)

# Function to return turn list of features that touch each feature into a table
Watercourse_Connected_to_Sea_Touching_DF <- function(idx)  {
  data.frame(Origin_Feature = rep(Watercourse_Connected_to_Sea_and_Sea$osid[idx], length(Watercourse_Connected_to_Sea_Touching_List[[idx]])), 
             Touching_Feature = Watercourse_Connected_to_Sea_and_Sea$osid[Watercourse_Connected_to_Sea_Touching_List[[idx]]])
}

# Table with origin and touching features in 'Watercourse_Connected_to_Sea_and_Sea'
Watercourse_Connected_to_Sea_Touching <- purrr::map_dfr(seq_along(Watercourse_Connected_to_Sea_Touching_List), Watercourse_Connected_to_Sea_Touching_DF) %>%
	left_join(.,Watercourse_Connected_to_Sea_and_Sea %>% st_drop_geometry %>% select(osid, description, watertype), join_by(Origin_Feature == osid)) %>%
	rename(Origin_Description = description, Origin_Watertype = watertype) %>%
	left_join(.,Watercourse_Connected_to_Sea_and_Sea %>% st_drop_geometry %>% select(osid, description, watertype), join_by(Touching_Feature == osid)) %>%
	rename(Touching_Description = description, Touching_Watertype = watertype) %>%
	as_tibble()

# Table with all features that touch the sea and at least one other watercourse feature
### Why? The aim is to remove rivers but retain more substantial water bodies
### The logic is as tributaries and narrow river channels have already been removed, most tidal features that are rivers will not touch another watercourse feature
### More substantial watercourse features will have multiple watercourse features that are still touching them so will be retained
Watercourse_Connected_to_Sea_Multiple_Intersects_List <- Watercourse_Connected_to_Sea_Touching %>% 
	filter(Origin_Feature %in% Watercourse_Touching_Sea$osid) %>%
	group_by(Origin_Feature) %>%
	summarise(Sea_Intersect = sum(str_count(Touching_Description , 'Sea')),
		Watercourse_Intersect = sum(str_count(Touching_Description , 'Watercourse'))) %>%
	filter(Sea_Intersect > 0 & Watercourse_Intersect > 0)

# Filter 'Watercourse_Connected_to_Sea' so only features that are touching the sea and at least one other watercourse feature are included
Watercourse_Connected_to_Sea_Multiple_Intersects <- Watercourse_Connected_to_Sea %>%
	filter(osid %in% Watercourse_Connected_to_Sea_Multiple_Intersects_List$Origin_Feature) 

# Filter 'Touching_Water_Subset_Features' by 'Watercourse_Connected_to_Sea_Multiple_Intersects' and create a list of unique identifies from 'Origin_Feature' and 'Touching_Feature'
Non_BUA_Watercourses_to_Retain <- Touching_Water_Subset_Features %>%
	filter(Origin_Feature %in% Watercourse_Connected_to_Sea_Multiple_Intersects$osid) %>%
	select(Origin_Feature, Touching_Feature) %>%
	unlist() %>%
	unique()

# Filter 'Water_Subset' by list of unique IDs in 'Non_BUA_Watercourses_to_Retain' and are watercourses
### Why? This creates a final selection of substantial water bodies that do not intersect BUAs with rivers and other more liner features having been removed.
Water_Subset_Non_BUA_Watercourses <- Water_Subset %>%
	select(osid, description, watertype) %>%
	filter(osid %in% Non_BUA_Watercourses_to_Retain & description == "Watercourse")

##### JOINING SELECTED WATERCOURSE FEATURES THAT INTERSECT WITH BUAS WITH SELECTED WATERCOURSE FEATURES THAT DO NOT INTERSECT WITH BUAS #####

# Select features from 'Water_Subset' that are within 'Watercourse_Union_BUA_Intersection_Touching_Sea'
### Why? This selects the original features, rather than the features that had been joined together in a previous step
Water_Subset_BUA_Touching_Sea <- Water_Subset %>%
	select(osid, description, watertype) %>%
	st_filter(., Watercourse_Union_BUA_Intersection_Touching_Sea, .predicate = st_within)

# Join 'Water_Subset_BUA_Touching_Sea' and 'Water_Subset_Non_BUA_Watercourses'
### Why? This creates a subset of watercourse features that either intersect with BUAs that are near the coast or are substantial water bodies that don't intersect with BUAs
Watercourse_Selection <- bind_rows(Water_Subset_BUA_Touching_Sea, Water_Subset_Non_BUA_Watercourses)

# Filter 'Watercourse_Union' so only features from 'Watercourse_Selection' that intersect with it remain
Watercourse_Selection_Union <- Watercourse_Union %>%
	st_filter(., Watercourse_Selection, .predicate = st_intersects)

# Filter 'Water_Subset' to only contain 'Sea' features
Water_Subset_Sea <- Water_Subset %>%
	filter(description == "Sea")

# Buffer 'Water_Subset_Sea' by 100 metres
### Why? This is so in the next step, features that are within 100 metres of the sea, rather than touching the sea, can be kept 
Water_Subset_Sea_Buffer <- Water_Subset_Sea %>%
	st_buffer(.,100, endCapStyle="FLAT")

# Negatively buffer 'Watercourse_Selection_Union' by 100 metres and then positively buffer by 100 metres
# Then filter remaining objects that intersect with 'Water_Subset_Sea_Buffer'
### Why? This is so narrow channels (most likely rivers) that are in 'Watercourse_Selection_Union' are removed and only features within 100 metres of the sea are kept
Buffer_Touching_Sea_Buffer <- Watercourse_Selection_Union %>%
	st_buffer(.,-100, endCapStyle="FLAT")  %>%
	st_buffer(.,100, endCapStyle="FLAT") %>%
	filter(!st_is_empty(.)) %>%
	st_collection_extract(., "POLYGON") %>%
	st_cast("POLYGON") %>%
	st_filter(., Water_Subset_Sea_Buffer %>%
		select(osid, description, watertype) %>%
		filter(description == "Sea"), .predicate = st_intersects)
		
# Filter 'Water_Subset' to include only watercourse features that intersect with 'Buffer_Touching_Sea_Buffer'	
Buffer_Touching_Sea_Buffer_Features <- Water_Subset %>%
	select(osid, description, watertype) %>%
	filter(description == "Watercourse") %>%
	st_filter(., Buffer_Touching_Sea_Buffer, .predicate = st_intersects)

# Select all the 1km grid cells that intersect with 'Buffer_Touching_Sea_Buffer'
# Why? This is so the smaller extremities of large water bodies can be removed in later steps 
ONS_Grid_1km_Touching_Sea_Buffer <- OS_Grid_1km_Tiles_UK[Buffer_Touching_Sea_Buffer,]

# Add field to indicate if 1km grid cells intersect with 'ONS_Grid_1km_Touching_Sea_Buffer' and filter to include only cells where they do
ONS_Grid_1km_Touching_Sea_Buffer_Tiles <- OS_Grid_1km_Tiles_UK %>% 
	select(-BUA_INTERSECT) %>%
	mutate(INCLUDE = case_when(
		OS_Grid_Reference %in% ONS_Grid_1km_Touching_Sea_Buffer$OS_Grid_Reference == TRUE ~ "TRUE",
		TRUE ~ "FALSE")) %>%
	relocate(INCLUDE, .after = OS_Grid_Reference) %>%
	filter(INCLUDE == TRUE)

# Cookie-cut 'Buffer_Touching_Sea_Buffer_Features' fetures with 'ONS_Grid_1km_Touching_Sea_Buffer_Tiles' 
### Why? This is so only features/parts of features that are within 1km grid cells are kept.
### This is to reduce the size of some large water bodies by removing smaller features to prevent them going too far inland
Buffer_Touching_Sea_Buffer_Features_Intersection <- Buffer_Touching_Sea_Buffer_Features %>%
	st_intersection(., ONS_Grid_1km_Touching_Sea_Buffer_Tiles) %>%
	st_collection_extract(., "POLYGON") %>%
	st_cast("POLYGON") 

# Merge features that are touching in 'Buffer_Touching_Sea_Buffer_Features_Intersection' and filter so only features that intersect with 'Water_Subset_Sea_Buffer are included
Buffer_Touching_Sea_Buffer_Features_Intersection_Union <- Buffer_Touching_Sea_Buffer_Features_Intersection %>%
	st_union(.) %>%
	st_cast("POLYGON") %>% 
	st_sf() %>%
	st_filter(., Water_Subset_Sea_Buffer %>%
		select(osid, description, watertype) %>%
		filter(description == "Sea"), .predicate = st_intersects)

# Join 'Buffer_Touching_Sea_Buffer_Features_Intersection_Union' with 'Sea' features
### This creates the final selection of features from the 'Water' input
Sea_and_Watercourses <- bind_rows(Water_Subset_Sea %>% select(geometry), Buffer_Touching_Sea_Buffer_Features_Intersection_Union)

##### SELECTING TIDAL LAND FEATURES #####

# Filter features in 'Land_Tidal' that intersect with 'Sea_and_Watercourses'
### Why? This is so only tidal land that touches the selected sea and watercourse features are selected
paste0("Stated: ", Sys.time(), " - takes 1 hour 15 minutes")
Tidal_Touching_Sea_and_Watercourses <- Land_Tidal %>% 
	select(osid, description)%>%
	st_filter(., Sea_and_Watercourses, .predicate = st_touches)

# Join 'Tidal_Touching_Sea_and_Watercourses' with 'Sea_and_Watercourses' features
### This creates the final selection of features to be used to cookie-cut full extent of realm (low-water mark) boundaries
Sea_Watercourses_Tidal <- bind_rows(Sea_and_Watercourses, Tidal_Touching_Sea_and_Watercourses %>% select(geometry))

##### CREATING FINAL GB SHORELINE #####

# Cookie-cut 'GB_BFE' using 'Sea_Watercourses_Tidal'
paste0("Stated: ", Sys.time(), " - takes 20 minutes")
GB_BFE_without_Sea_Watercourses_Tidal <- st_difference(GB_BFE, st_union(Sea_Watercourses_Tidal))

# Convert 'GB_BFE_without_Sea_Watercourses_Tidal' from being a Multipart Polygon to single polygons
GB_BFE_without_Sea_Watercourses_Tidal_Single_Part <- GB_BFE_without_Sea_Watercourses_Tidal %>%
	st_cast("POLYGON") %>%
	mutate(ID = paste0("id_",row_number()),
		Area_m2 = as.numeric(st_area(.))) %>%
	arrange(-Area_m2)

# Ensure 'GB_BFC' boundaries are valid
GB_BFC <- GB_BFC %>%
	st_make_valid()

# Filter 'GB_BFE_without_Sea_Watercourses_Tidal_Single_Part' to include only features that intersect with 'GB_BFC'
### Why? This is so small islands and data artifacts are removed
paste0("Stated: ", Sys.time(), " - takes 1 hour 30 minutes")
GB_BFE_without_Sea_Watercourses_Tidal_Single_Part_BFC_Intersect <- GB_BFE_without_Sea_Watercourses_Tidal_Single_Part %>%
	st_filter(., GB_BFC, .predicate = st_intersects)

# Creates a Multipart Polygon of the GB shoreline by each country 
GB_Shoreline <- GB_BFE_without_Sea_Watercourses_Tidal_Single_Part_BFC_Intersect %>%
	group_by(CTRY22CD) %>%
	summarise(geometry = st_union(geometry)) %>%
	ungroup()

# Converts 'GB_Shoreline' to be a polyline
paste0("Stated: ", Sys.time(), " - takes 5 minutes")
GB_Shoreline_Polyline <- GB_Shoreline %>%
	st_union(.) %>%
	st_cast(.,"MULTILINESTRING")

# Export outputs
st_write(GB_Shoreline, paste0("[DIRECTORY_PATH]/GB_Shoreline_",OS_Data_Month_Year,".gpkg"))
st_write(GB_Shoreline_Polyline, paste0("[DIRECTORY_PATH]/GB_Shoreline_Polyline_",OS_Data_Month_Year,".gpkg"))

End_Time <- Sys.time()

Start_Time
End_Time 
End_Time - Start_Time
