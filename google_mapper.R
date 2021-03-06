# Author: Kenneth Schackart
#  Email: schackartk1@gmail.com

suppressWarnings(suppressMessages(library(tidyverse))) # Of course
suppressWarnings(suppressMessages(library(leaflet))) # For making beautiful maps
suppressWarnings(suppressMessages(library(leaflet.extras))) # Necessary for heatmap()
suppressWarnings(suppressMessages(library(lubridate))) # For working with dates/times
suppressWarnings(suppressMessages(library(jsonlite))) # Handles JSON files from Google Takeout
suppressWarnings(suppressMessages(library(htmlwidgets))) # Saving HTML widget as .html file

# This script is essentially a single function
# It is called by either executable_google_mapper.R or IDE_google_mapper.R

map_data <- function(files) {

  # Extract file names from function call

  ratings_file <- files["ratings"]
  loc_hist_file <- files["location"]
  label_file <- files["labels"]
  out_file <- files["outfile"]

  # Functions ---------------------------------------------------------------

  tidy_json <- function(f) {

    # Try to parse file as json, if it fails, return NA

    out <- tryCatch(
      {
        fromJSON(f) %>%
          as_tibble() %>%
          flatten() %>%
          as_tibble()
      },
      error = function(cond) {
        message(paste("\nUnable to interpret file:", f, "as '.json'... Skipping."))
        return(NA)
      }
    )
    return(out)
  }

  clean_ratings <- function(df, f) {
    out <- tryCatch(
      {
        
        # Filter out unnecessary columns
        
        df <- df %>%
          select(
            "features.properties.Google Maps URL", 
            "features.properties.Published",
            "features.properties.Star Rating",
            "features.properties.Review Comment",
            "features.properties.Location.Address",
            "features.properties.Location.Business Name",
            "features.properties.Location.Geo Coordinates.Latitude",
            "features.properties.Location.Geo Coordinates.Longitude"
        )

        # Rename columns to make more sense
        
        df <- df %>%
          rename("maps_url" = "features.properties.Google Maps URL") %>%
          rename("date_time" = "features.properties.Published") %>%
          rename("rating" = "features.properties.Star Rating") %>%
          rename("review" = "features.properties.Review Comment") %>%
          rename("address" = "features.properties.Location.Address") %>%
          rename("business_name" = "features.properties.Location.Business Name") %>%
          rename("latitude" = "features.properties.Location.Geo Coordinates.Latitude") %>%
          rename("longitude" = "features.properties.Location.Geo Coordinates.Longitude")

        # Fix time formatting and data type
        
        df$date_time <- df$date_time %>%
          gsub(pattern = "T", replacement = " ") %>%
          gsub(pattern = "Z", replacement = "") %>%
          ymd_hms()

        # Change $rating column to factor
        
        df$rating <- as.factor(df$rating) %>%
          factor(levels = c("1", "2", "3", "4", "5"))

        # Convert latitude and longitude to numeric type
        
        df$latitude <- as.numeric(df$latitude)
        df$longitude <- as.numeric((df$longitude))

        df
      },
      error = function(cond) {
        message(paste("\nUnable to interpret file", f, "in context as ratings file."))
        message(paste("Please ensure that you meant this file to be interpreted as ratings/reviews."))
        message("Skipping.")
        return(NA)
      }
    )
    return(out)
  }

  clean_history <- function(df, f) {
    out <- tryCatch(
      {
        df <- df %>%
          select(locations.latitudeE7, locations.longitudeE7)

        df <- df %>%
          rename("latitude" = "locations.latitudeE7") %>%
          rename("longitude" = "locations.longitudeE7")
        
        df <- na.omit(df)
        
        # Rescale data since they are originally recorded as *10^7
        
        df <- df * 10^-7

        df
      },
      error = function(cond) {
        message(paste("\nUnable to interpret file", f, "in context as location history file."))
        message(paste("Please ensure that you meant this file to be interpreted as location history."))
        message("Skipping.")
        return(NA)
      }
    )
    return(out)
  }

  clean_labels <- function(df, f) {
    out <- tryCatch(
      {
        df <- df %>%
          select(features.geometry.coordinates, features.properties.address, features.properties.name)

        df <- df %>%
          rename("coords" = "features.geometry.coordinates") %>%
          rename("address" = "features.properties.address") %>%
          rename("name" = "features.properties.name")

        latitude <- str_match(df$coords, "[[:digit:]]+\\.[[:digit:]]+[,]") %>%
          gsub(pattern = ",", replacement = "")

        longitude <- str_match(df$coords, ".[[:digit:]]+\\.[[:digit:]]+[\\)]") %>%
          gsub(pattern = ")", replacement = "") %>%
          trimws()

        df <- df %>%
          add_column(latitude, longitude) %>%
          select(-coords)

        df$latitude <- as.numeric(df$latitude)
        df$longitude <- as.numeric(df$longitude)

        df
      },
      error = function(cond) {
        message(paste("\nUnable to interpret file", f, "in context as labeled places file."))
        message(paste("Please ensure that you meant this file to be interpreted as labeled places."))
        message("Skipping.")
        return(NA)
      }
    )


    return(out)
  }

  map_ratings <- function(df, m) {
    
    color_pal <- "RdYlGn"
    
    pal <- colorFactor(color_pal, df$rating)
    
    # Make labels for legend using star symbol (\u2605)
    
    labels <- c()
    
    for(level in rev(levels(df$rating)))
      labels <- labels %>% append(
        paste(unlist(rep("\u2605", times = level)),
              collapse = ""
        ))

    m <- m %>%
      addCircleMarkers(
        group = "Ratings", data = df,
        ~longitude, ~latitude,
        radius = 8, weight = 1, color = "#777777",
        fillColor = ~ pal(rating), fillOpacity = 0.7,
        popup = ~ paste0(
          "<b><a href='", maps_url, "' target='_blank'>",
          business_name, "</a></b>",
          "<br>",
          "Rating: ", lapply(
            rating,
            function(x) {
              paste(unlist(rep("\u2605", times = x)),
                collapse = ""
              )
            }
          ),
          "<br>",
          lapply(
            review,
            function(x) if (!is.na(x)) "Review: " else ""
          ),
          lapply(
            review,
            function(x) if (!is.na(x)) x else ""
          )
        )
      ) %>%
      addLegend(
        group = "Ratings", position = "bottomright",
        title = "Place Rating", values = levels(df$rating),
        pal = colorFactor(color_pal, df$rating, reverse = TRUE),
        labFormat = function(type, cuts, p) {paste0(labels)}
        )
    
    return(m)
  }

  map_loc_hist <- function(df, m) {
    m <- m %>%
      addHeatmap(
        data = df, group = "Location Heatmap",
        blur = 30, radius = 15, max = 0.85, gradient = "Blues"
      )
    return(m)
  }

  map_labels <- function(df, m) {
    m <- m %>%
      addMarkers(
        group = "Labeled Places", data = df, ~longitude, ~latitude,
        popup = paste0("Label: ", df$name, "<br>", "Address: ", df$address)
      )
  }

  # Main --------------------------------------------------------------------

  # Initialize an empty map

  my_map <- leaflet() %>%
    addTiles(group = "OSM (default)", attribution = paste0(
      "Source code: <a href='https://github.com/schackartk/google_mapper' target= '_blank'",
      " title = 'google_mapper GitHub repository' >google_mapper</a>,",
      " by <a href='https://twitter.com/SchackartK' target= '_blank'",
      " title = 'Author twitter' >@SchackartK</a>"
    ))
  layers <- NULL

  # Add layers for files that are present

  file_labels <- c("ratings", "location history", "labeled places")
  layer_labels <- c("Ratings", "Location Heatmap", "Labeled Places")
  file_names <- c(ratings_file, loc_hist_file, label_file)
  names(layer_labels) <- file_labels
  names(file_names) <- file_labels

  for (fn in file_labels) {

    # Check that there is a file at the given path
    
    if (file.exists(file_names[[fn]])) {
      message(paste("Processing", fn, "file... "), appendLF = FALSE)
      raw_data <- tidy_json(file_names[[fn]])

      # Check that data parsing went ok
      
      suppressWarnings(if (!is.na(raw_data)) {
        
        # If the file could be parsed as a json file, I am going to assume it is in the right format

        # Work with and map each data set with its own treatment
        
        if (fn == "ratings") {
          cleaned_ratings <- clean_ratings(raw_data, file_names[[fn]])
          # If data could be interpreted in context, plot it.
          suppressWarnings(if (!is.na(cleaned_ratings)) {
            my_map <- map_ratings(cleaned_ratings, my_map)
            layers <- append(layers, layer_labels[[fn]])
          })
        } else if (fn == "location history") {
          cleaned_loc_hist <- clean_history(raw_data, file_names[[fn]])
          suppressWarnings(if (!is.na(cleaned_loc_hist)) {
            my_map <- map_loc_hist(cleaned_loc_hist, my_map)
            layers <- append(layers, layer_labels[[fn]])
          })
        } else if (fn == "labeled places") {
          cleaned_labs <- clean_labels(raw_data, file_names[[fn]])
          suppressWarnings(if (!is.na(cleaned_labs)) {
            my_map <- map_labels(cleaned_labs, my_map)
            layers <- append(layers, layer_labels[[fn]])
          })
        }

        message(paste("Done processing", fn, "file."))
      })
    } else {
      message(paste0("No ", fn, " file found: '", file_names[[fn]], "'. Skipping."))
    }
  }

  # Check that layers are present
  
  if (is.null(layers)) {
    message("Unable to find any usable files, no output can be generated.")
    message("Please ensure that the provided file paths are correct.")
  } else {

    # Add a control to toggle layers
    
    my_map <- my_map %>% addLayersControl(
      overlayGroups = layers
    )

    # Save html map widget
    
    message("Saving map output.")
    saveWidget(my_map, out_file)

    message(paste0("Done, see file: '", out_file, "'!"))
  }
}
