# Load libraries and graph data ----
library(igraph)
library(RColorBrewer)
source('Graph Generation.R')

# Plot setup ----

# Visually cluster facilities according to the transfers between them
layout_by_denominator <- function(seed = 85, layout_csv = NA){

  # If there's a file you want to load for the layout, load it
  if (!(is.na(layout_csv))) {
    weighted_layout <- as.matrix(read.csv(layout_csv, header = FALSE))
    dimnames(weighted_layout) <- NULL
    return(weighted_layout)
  }

  # Create a communities object weighted according to the denominator transfers
  # NOTE: Depending on your computing power and number of points, this may take a while.
  # Or forever. It worked for me after a couple minutes
  c <- cluster_optimal(g, weights = abs(E(g)$transfers))

  # Create a layout based on communities
  edge_weights <- ifelse(crossing(c, g), 1, 70)

  # Set the randomness seed to create a reproducible layout
  set.seed(seed)
  weighted_layout <- layout_with_fr(g, weights = edge_weights, coords = layout_with_kk(g, weights = edge_weights))

  # Find outlying points
  x_extremes <- boxplot.stats(weighted_layout[,1])$stats[c(1,5)]
  y_extremes <- boxplot.stats(weighted_layout[,2])$stats[c(1,5)]
  x_outliers <- which(weighted_layout[,1] %in% boxplot.stats(weighted_layout[,1])$out)
  y_outliers <- which(weighted_layout[,2] %in% boxplot.stats(weighted_layout[,2])$out)

  # Bring outlying points closer and give them a random position at their appropriate extreme
  # NOTE: May be misleading, these can look like clustered points even if they're not
  for (x in x_outliers) {
    if (weighted_layout[x,1] < x_extremes[1]) {
      weighted_layout[x,1] <- x_extremes[1] - runif(1, max = 0.5)
    } else {
      weighted_layout[x,1] <- x_extremes[2] + runif(1, max = 0.5)
    }
  }
  for (y in y_outliers) {
    if (weighted_layout[y,2] < y_extremes[1]) {
      weighted_layout[y,2] <- y_extremes[1] - runif(1, max = 0.5)
    } else {
      weighted_layout[y,2] <- y_extremes[2] + runif(1, max = 0.5)
    }
  }

  return(weighted_layout)

}

# Set shapes for vertices according to facility type
generate_node_shapes <- function(){

  node_shapes_opts <- c('triangle', 'circle', 'square', 'diamond')
  names(node_shapes_opts) <- unique(V(g)$type)
  return(node_shapes_opts[V(g)$type])

}

# Plotting ----
plot_network <- function(label_clusters = FALSE, node_sizes = c('uniform', 'stays'),
                            node_colors = c('cluster', 'cases', 'prevalence'),
                            edges_to_plot = c('suppress', 'ari', 'all'),
                            edge_colors = c('denominator', 'ari', 'percent_ari'),
                            edge_widths = c('uniform', 'transfers', 'ari'),
                            highlight_facility = c(FALSE, TRUE)){

  # Set node sizes according to node_sizes ----
  node_sizes <- match.arg(node_sizes)

  if (node_sizes == 'stays'){

    # Logs of the absolute value capture different orders of magnitude, and also make censored (negative) values
    # disappear
    V(g)$size <- log(abs(V(g)$stays), 5)
  } else {
    V(g)$size <- 2.5
  }

  # Set node coloration according to node_colors ----
  node_colors <- match.arg(node_colors)

  if (node_colors == 'cluster') {

    # Color the nodes according to their cluster

    # https://stackoverflow.com/questions/15282580/how-to-generate-a-number-of-most-distinctive-colors-in-r
    qual_col_pals <- brewer.pal.info[brewer.pal.info$category == 'qual',]
    col_vector <- unlist(mapply(brewer.pal, qual_col_pals$maxcolors, rownames(qual_col_pals)))
    V(g)$color <- col_vector[c$membership]

  } else if (node_colors == 'cases') {

    # Color the nodes according to the number of cases they have
    col_vector <- rev(heat.colors(max(V(g)$cases) + 1))
    V(g)$color <- col_vector[V(g)$cases + 1]

  } else if (node_colors == 'prevalence') {

    # The percentage is 100 * prevalence, so take the log of that to smooth it out
    logged <- log10(V(g)$prevalence * 100)

    # Find the coloration thresholds according to boxplot stats, without infinite
    thresholds <- boxplot.stats(logged[-which(is.infinite(logged))])$stats

    # Set a palette and pick colors according to where the node is in the boxplot
    heat_vector <- rev(heat.colors(6))
    V(g)$color <- vapply(logged, function(x){
      if (is.infinite(x)) {
        return('#FFFFFF')  # Prevalence of 0
      } else if (x <= thresholds[1]) {
        return(heat_vector[1])
      } else if (x <= thresholds[2]) {
        return(heat_vector[2])
      } else if (x <= thresholds[3]) {
        return(heat_vector[3])
      } else if (x <= thresholds[4]) {
        return(heat_vector[4])
      } else if (x <= thresholds[5]) {
        return(heat_vector[5])
      } else {
        return(heat_vector[6])
      }
    }, character(1), USE.NAMES = FALSE)
  }

  # Highlight bridging facility according to highlight_facility ----
  # Note: Because the bridging facility is identified by it's ID, it's manually added in every time
  if (highlight_facility) {
    V(g)$color[which(V(g)$name == facility_to_highlight)] <- 'blue'
  }

  # Set edge types according to edges_to_plot ----
  edges_to_plot = match.arg(edges_to_plot)

  # If you wanna plot all edges, assign ltys according to number of trasnfers
  if (edges_to_plot == 'all') {
    E(g)$lty <- vapply(E(g)$transfers, function(x){

      # Suppress plotting of edges with less then 10 transfers
      if (x < 35) {
        return(0)
      }
      # Dashed lines for less than 50 transfers
      else if (x < 100) {
        return(2)
      }
      # Solid lines for more than 50 transfers
      else {
        return(1)
      }
    }, double(1), USE.NAMES = FALSE)
  } else if (edges_to_plot == 'ari') {

    # If there's ARI, plot it. Otherwise, don't
    E(g)$lty <- vapply(E(g)$ari, function(x){
      if (x == 0) return(0) else return(1)
    }, double(1), USE.NAMES = FALSE)

  } else if (edges_to_plot == 'suppress') {
    # Suppress plotting
    E(g)$lty <- 0
  }

  # Give a dotted line for edges that have less than 10 transfers, but contain ARI
  if (edge_colors == 'ari' || edge_colors == 'percent_ari'){
    E(g)$lty[which(E(g)$lty == 0 & E(g)$ari > 0)] <- 3
  }

  # Set edge colors according to edge_colors ----
  edge_colors <- match.arg(edge_colors)

  if (edge_colors == 'denominator') {

    E(g)$color <- 'gray'

  } else if (edge_colors == 'ari') {

    # Create a heat colors vector with a grey for edges with 0 cases
    col_vector <- c(adjustcolor('grey', alpha.f = 0.1), rev(heat.colors(max(E(g)$ari))))
    E(g)$color <- col_vector[E(g)$ari + 1]

  } else if (edge_colors == 'percent_ari') {

    # Pre-emptively assign all edges a light faded grey
    E(g)$color <- adjustcolor('grey', alpha.f = 0.1)

    # For edges that have a non-zero ARI percentage, assign them a color from the heatmap
    col_vector <- rev(heat.colors(max(round(E(g)$percent_ari * 1000))))
    E(g)$color[which(E(g)$ari != 0)] <- col_vector[round(E(g)$percent_ari * 1000)]

  }

  # Set edge_widths according to edge_widths ----
  edge_widths <- match.arg(edge_widths)

  if (edge_widths == 'uniform') {
    E(g)$widths <- 1
  } else if (edge_widths == 'transfers') {
    E(g)$widths <- vapply(E(g)$transfers, function(x){

      if (x <= 0) {
        return(0.5)
      } else {
        return(log10(x))
      }
    }, double(1), USE.NAMES = FALSE)
  } else if (edge_widths == 'ari') {
    E(g)$widths <- vapply(E(g)$ari, function(x){

      if (x <= 0) {
        return(0.5)
      } else {
        return(log2(x + 1))
      }
    }, double(1), USE.NAMES = FALSE)
  }

  # Final plot setup and output to device ----
  # Set the plot's limits to be slightly bigger than the plot itself
  x_max <- max(l[,1]) + abs(mean(l[,1])) * 0.001
  x_min <- min(l[,1]) - abs(mean(l[,1])) * 0.001
  y_max <- max(l[,2]) + abs(mean(l[,2])) * 0.001
  y_min <- min(l[,2]) - abs(mean(l[,2])) * 0.001

  # Figure out what the title should be
  if (edges_to_plot == 'suppress') {
    transfers <- 'Facilities'
  } else if (edges_to_plot == 'ari') {
    transfers <- 'ARI Transfers'
  } else {
    transfers <- 'All Medicare Transfers'
    subtitle <- '<35 Transfers not Plotted, 35-100 Transfers Dashed, >100 Transfers Solid'
  }
  plot_title <- paste(transfers, 'in the HD3 Area')

  plot(g, layout = l, xlim = c(x_min, x_max), ylim = c(y_min, y_max), rescale = FALSE,

       # Plot parameters
       main = plot_title,
       sub = subtitle,

       # Vertex parameters
       vertex.size = V(g)$size,
       vertex.color = V(g)$color,
       vertex.shape = V(g)$shape,

       # Vertex label parameters
       vertex.label = NA,

       # Edge parameters
       edge.lty = E(g)$lty,
       edge.col = E(g)$color,
       edge.width = E(g)$widths,

       # Arrow parameters
       edge.arrow.mode = 0)

  # Put some text down in the center of every group with the group label
  if(label_clusters){
    for (community in 1:length(c)) {

      # Find the locations of points of community members
      locs <- matrix(l[which(membership(c) == community),], ncol = 2)

      # Find the x and y means
      x_mean <- mean(locs[,1])
      y_mean <- mean(locs[,2])

      # Put some text there
      text(x_mean, y = y_mean, labels = community)
    }
  }

  # Create the legend according to what you plotted ----
  #legend('topleft', )

}

# Run this before plotting to ensure shapes actually happen ----

# Ripped from the docs, don't ask me how this works
mytriangle <- function(coords, v=NULL, params) {
  vertex.color <- params("vertex", "color")
  if (length(vertex.color) != 1 && !is.null(v)) {
    vertex.color <- vertex.color[v]
  }
  vertex.size <- 1/125 * params("vertex", "size")
  if (length(vertex.size) != 1 && !is.null(v)) {
    vertex.size <- vertex.size[v]
  }

  symbols(x=coords[,1], y=coords[,2], bg=vertex.color,
          stars=cbind(vertex.size, vertex.size, vertex.size),
          add=TRUE, inches=FALSE)
}
# clips as a circle
add_shape("triangle", clip=shapes("circle")$clip,
          plot=mytriangle)

# generic star vertex shape, with a parameter for number of rays
mystar <- function(coords, v=NULL, params) {
  vertex.color <- params("vertex", "color")
  if (length(vertex.color) != 1 && !is.null(v)) {
    vertex.color <- vertex.color[v]
  }
  vertex.size  <- 1/150 * params("vertex", "size")
  if (length(vertex.size) != 1 && !is.null(v)) {
    vertex.size <- vertex.size[v]
  }
  norays <- params("vertex", "norays")
  if (length(norays) != 1 && !is.null(v)) {
    norays <- norays[v]
  }

  mapply(coords[,1], coords[,2], vertex.color, vertex.size, norays,
         FUN=function(x, y, bg, size, nor) {
           symbols(x=x, y=y, bg=bg,
                   stars=matrix(c(size,size), nrow=1, ncol=nor*2),
                   add=TRUE, inches=FALSE)
         })
}
# no clipping, edges will be below the vertices anyway
add_shape("diamond", clip=shape_noclip,
          plot=mystar, parameters=list(vertex.norays=2))

# Generate globals for layout and clustering ----
l <- layout_by_denominator(layout_csv = 'Layout.csv')
set.seed(1)  # Consistent clustering
c <- cluster_optimal(g, weights = abs(E(g)$transfers))

# Set node shapes, too
V(g)$shape <- generate_node_shapes()

