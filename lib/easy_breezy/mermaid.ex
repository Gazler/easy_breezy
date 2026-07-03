defmodule EasyBreezy.Mermaid do
  @moduledoc false

  alias EasyBreezy.Mermaid.Parser

  defmodule Graph do
    @moduledoc false
    defstruct direction: :td, nodes: %{}, node_order: [], edges: [], class_defs: %{}
  end

  defmodule Node do
    @moduledoc false
    defstruct [:id, :label, :class_name, shape: :box]
  end

  defmodule Edge do
    @moduledoc false
    defstruct [:from, :to, :label]
  end

  def render(source, width, height) when is_binary(source) do
    render(source, width, height, truncate?: true)
  end

  def render(source, width, height, opts) when is_binary(source) and is_list(opts) do
    with {:ok, graph} <- parse(source) do
      ansi_restore = Keyword.get(opts, :ansi_restore, IO.ANSI.reset())
      rendered_lines = render_graph(graph, max(width, 1), ansi_restore)

      lines =
        if Keyword.get(opts, :truncate?, true) do
          fit_lines(rendered_lines, max(width, 1), max(height, 1))
        else
          wrap_lines(rendered_lines, max(width, 1))
        end

      {:ok, lines}
    end
  end

  def parse(source) when is_binary(source) do
    case Parser.parse_document(source) do
      {:error, :empty} ->
        {:error, "Mermaid diagram is empty"}

      {:ok, %{direction: direction, statements: statements}} ->
        build_graph(direction, statements)

      {:error, _reason} ->
        {:error, "Expected Mermaid flowchart or graph header"}
    end
  end

  defp build_graph(direction, statements) do
    parse_statements(statements, %Graph{direction: direction})
  end

  defp parse_statements(statements, graph) do
    Enum.reduce_while(statements, {:ok, graph}, fn statement, {:ok, graph} ->
      case parse_statement(statement, graph) do
        {:ok, graph} -> {:cont, {:ok, graph}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp parse_statement({:edge, parsed}, graph), do: add_edge(graph, parsed)

  defp parse_statement({:class_def, attrs}, graph) do
    with {:ok, name} <- Keyword.fetch(attrs, :name),
         {:ok, color} <- Keyword.fetch(attrs, :color) do
      {:ok, %{graph | class_defs: Map.put(graph.class_defs, name, %{color: "#" <> color})}}
    else
      :error -> {:error, "Unsupported Mermaid classDef syntax"}
    end
  end

  defp parse_statement({:node, node_token}, graph) do
    with {:ok, node} <- node_from_token(node_token) do
      {:ok, put_node(graph, node)}
    end
  end

  defp parse_statement(_statement, _graph), do: {:error, "Unsupported Mermaid statement syntax"}

  defp add_edge(graph, parsed) do
    with {:ok, from_node} <- parsed |> Keyword.fetch!(:from) |> node_from_token(),
         {:ok, to_node} <- parsed |> Keyword.fetch!(:to) |> node_from_token() do
      edge = %Edge{from: from_node.id, to: to_node.id, label: clean_label(parsed[:label])}

      graph =
        graph
        |> put_node(from_node)
        |> put_node(to_node)

      {:ok, %{graph | edges: graph.edges ++ [edge]}}
    end
  end

  defp node_from_token({shape, node_attrs}), do: node_from_attrs(shape, node_attrs)

  defp node_from_attrs(shape, node_attrs) do
    with {:ok, id} <- Keyword.fetch(node_attrs, :id) do
      label = node_attrs |> Keyword.get(:label, id) |> clean_label()
      {:ok, %Node{id: id, label: label, shape: shape, class_name: node_attrs[:class_name]}}
    else
      :error ->
        {:error, "Unsupported Mermaid node syntax"}
    end
  end

  defp clean_label(nil), do: nil

  defp clean_label(label) do
    label
    |> String.trim()
    |> String.trim_leading("\"")
    |> String.trim_trailing("\"")
  end

  defp put_node(%Graph{} = graph, %Node{} = node) do
    node_order =
      if Map.has_key?(graph.nodes, node.id),
        do: graph.node_order,
        else: graph.node_order ++ [node.id]

    nodes =
      Map.update(graph.nodes, node.id, node, fn existing ->
        cond do
          existing.label == existing.id and node.label != node.id ->
            merge_node(existing, node)

          is_nil(existing.class_name) and node.class_name ->
            %{existing | class_name: node.class_name}

          true ->
            existing
        end
      end)

    %{graph | nodes: nodes, node_order: node_order}
  end

  defp merge_node(existing, node),
    do: %{node | class_name: node.class_name || existing.class_name}

  defp render_graph(%Graph{direction: :lr} = graph, width, ansi_restore) do
    graph
    |> layers()
    |> render_lr(graph, width, ansi_restore)
  end

  defp render_graph(graph, width, ansi_restore) do
    graph
    |> layers()
    |> render_td(graph, width, ansi_restore)
  end

  defp layers(graph) do
    initial = Map.new(graph.node_order, &{&1, 0})

    ranks =
      Enum.reduce(1..max(length(graph.node_order), 1), initial, fn _pass, ranks ->
        Enum.reduce(graph.edges, ranks, fn edge, ranks ->
          from_rank = Map.get(ranks, edge.from, 0)
          to_rank = Map.get(ranks, edge.to, 0)

          if to_rank <= from_rank do
            Map.put(ranks, edge.to, from_rank + 1)
          else
            ranks
          end
        end)
      end)

    graph.node_order
    |> Enum.group_by(&Map.get(ranks, &1, 0))
    |> Enum.sort_by(fn {rank, _ids} -> rank end)
    |> Enum.map(fn {_rank, ids} -> ids end)
  end

  defp render_td(layers, graph, width, ansi_restore) do
    rendered_layers =
      Enum.map(layers, fn ids ->
        {node_lines, positions} = render_td_layer(ids, graph, width, ansi_restore)
        %{lines: node_lines, positions: positions}
      end)
      |> align_single_node_layers(graph)

    rendered_layers
    |> Enum.with_index()
    |> Enum.flat_map(fn {layer, index} ->
      previous = Enum.at(rendered_layers, index - 1)
      next = Enum.at(rendered_layers, index + 1)

      incoming_edges =
        if previous, do: td_edges(previous.positions, layer.positions, graph), else: []

      outgoing_edges = if next, do: td_edges(layer.positions, next.positions, graph), else: []

      node_lines =
        layer.lines
        |> add_td_layer_arrows(layer.positions, incoming_edges)
        |> add_td_layer_outgoing_joins(layer.positions, outgoing_edges)

      connector_lines =
        if next do
          render_td_connectors(layer.positions, next.positions, graph, width)
        else
          []
        end

      node_lines ++ connector_lines
    end)
  end

  defp render_td_layer(ids, graph, width, ansi_restore) do
    box_entries =
      for id <- ids do
        box = node_box(Map.fetch!(graph.nodes, id), graph.class_defs, ansi_restore)
        [top | _] = box
        {id, box, String.length(top)}
      end

    box_widths = for {_id, _box, width} <- box_entries, do: width
    total_width = Enum.sum(box_widths) + max(length(box_entries) - 1, 0) * 4
    left = max(div(width - total_width, 2), 0)

    max_height =
      box_entries |> Enum.map(fn {_id, box, _width} -> length(box) end) |> Enum.max(fn -> 0 end)

    positions =
      Enum.reduce(box_entries, {%{}, left}, fn {id, _box, box_width}, {positions, x} ->
        center = x + div(box_width - 1, 2)
        {Map.put(positions, id, %{left: x, center: center}), x + box_width + 4}
      end)
      |> elem(0)

    lines =
      for row <- 0..(max_height - 1) do
        {line, _x} =
          Enum.reduce(box_entries, {spaces(left), left}, fn {_id, box, box_width}, {line, x} ->
            text = Enum.at(box, row, spaces(box_width))

            {line <> spaces(max(x - visible_length(line), 0)) <> text <> spaces(4),
             x + box_width + 4}
          end)

        String.trim_trailing(line)
      end

    {lines, positions}
  end

  defp align_single_node_layers(rendered_layers, graph) do
    rendered_layers
    |> Enum.reduce([], fn layer, aligned_layers ->
      case List.last(aligned_layers) do
        nil -> [layer]
        previous -> aligned_layers ++ [align_single_node_layer(previous, layer, graph)]
      end
    end)
  end

  defp align_single_node_layer(previous, current, graph) do
    incoming_edges = td_edges(previous.positions, current.positions, graph)

    with true <- map_size(previous.positions) == 1,
         true <- map_size(current.positions) == 1,
         [edge] <- incoming_edges,
         %{center: source_center} <- Map.get(previous.positions, edge.from),
         %{center: target_center} <- Map.get(current.positions, edge.to) do
      shift = source_center - target_center

      if shift != 0 and abs(shift) <= 2 and can_shift_layer?(current, shift) do
        shift_layer(current, shift)
      else
        current
      end
    else
      _ -> current
    end
  end

  defp can_shift_layer?(%{positions: positions}, shift) when shift < 0 do
    Enum.all?(positions, fn {_id, %{left: left}} -> left + shift >= 0 end)
  end

  defp can_shift_layer?(_layer, _shift), do: true

  defp shift_layer(layer, shift) do
    %{
      layer
      | lines: Enum.map(layer.lines, &shift_line(&1, shift)),
        positions:
          Map.new(layer.positions, fn {id, position} ->
            {id, %{position | left: position.left + shift, center: position.center + shift}}
          end)
    }
  end

  defp shift_line(line, shift) when shift > 0, do: spaces(shift) <> line

  defp shift_line(line, shift) when shift < 0 do
    remove_leading_spaces(line, -shift)
  end

  defp shift_line(line, _shift), do: line

  defp remove_leading_spaces(line, 0), do: line

  defp remove_leading_spaces(" " <> rest, count) do
    remove_leading_spaces(rest, count - 1)
  end

  defp remove_leading_spaces(line, _count), do: line

  defp render_td_connectors(previous, current, graph, width) do
    edges = td_edges(previous, current, graph)

    if edges == [] do
      [""]
    else
      if straight_vertical_connectors?(edges, previous, current) do
        render_straight_td_connectors(edges, previous, current, width)
      else
        render_routed_td_connectors(edges, previous, current, width)
      end
    end
  end

  defp straight_vertical_connectors?(edges, previous, current) do
    Enum.all?(edges, fn edge ->
      {sx, tx} = connector_centers(previous[edge.from].center, current[edge.to].center)
      sx == tx
    end)
  end

  defp render_straight_td_connectors(edges, previous, current, width) do
    vertical = blank_chars(width)

    vertical =
      Enum.reduce(edges, vertical, fn edge, vertical ->
        {sx, _tx} = connector_centers(previous[edge.from].center, current[edge.to].center)

        case edge.label do
          nil -> replace_at(vertical, sx, "│")
          "" -> replace_at(vertical, sx, "│")
          label -> put_centered_text(vertical, label, sx)
        end
      end)

    [vertical]
    |> Enum.map(&(&1 |> Enum.join() |> String.trim_trailing()))
    |> Enum.reject(&(&1 == ""))
  end

  defp render_routed_td_connectors(edges, previous, current, width) do
    horizontal = blank_chars(width)

    horizontal =
      Enum.reduce(edges, horizontal, fn edge, horizontal ->
        {sx, tx} = routed_connector_centers(edge, edges, previous, current)
        mid = div(sx + tx, 2)

        horizontal =
          horizontal
          |> put_horizontal_range(min(sx, tx), max(sx, tx))
          |> replace_connector_at(sx, "┴")
          |> replace_connector_at(tx, child_join_char(edge, edges, current))

        if edge.label in [nil, ""] do
          horizontal
        else
          put_centered_text(horizontal, edge.label, mid)
        end
      end)

    [horizontal]
    |> Enum.map(&(&1 |> Enum.join() |> String.trim_trailing()))
    |> Enum.reject(&(&1 == ""))
  end

  defp add_td_layer_arrows([], _positions, _incoming_edges), do: []
  defp add_td_layer_arrows(lines, _positions, []), do: lines

  defp add_td_layer_arrows([top | rest], positions, incoming_edges) do
    arrow_columns = for edge <- incoming_edges, uniq: true, do: positions[edge.to].center

    top =
      arrow_columns
      |> Enum.reduce(String.graphemes(top), fn column, chars ->
        replace_at(chars, column, "▼")
      end)
      |> Enum.join()

    [top | rest]
  end

  defp add_td_layer_outgoing_joins([], _positions, _outgoing_edges), do: []
  defp add_td_layer_outgoing_joins(lines, _positions, []), do: lines

  defp add_td_layer_outgoing_joins(lines, positions, outgoing_edges) do
    join_columns = for edge <- outgoing_edges, uniq: true, do: positions[edge.from].center

    List.update_at(lines, length(lines) - 1, fn bottom ->
      join_columns
      |> Enum.reduce(String.graphemes(bottom), fn column, chars ->
        replace_at(chars, column, "┬")
      end)
      |> Enum.join()
    end)
  end

  defp td_edges(previous, current, graph) do
    for edge <- graph.edges,
        Map.has_key?(previous, edge.from),
        Map.has_key?(current, edge.to),
        do: edge
  end

  defp connector_centers(source_center, target_center)
       when abs(source_center - target_center) <= 2 do
    center = div(source_center + target_center, 2)
    {center, center}
  end

  defp connector_centers(source_center, target_center), do: {source_center, target_center}

  defp routed_connector_centers(edge, edges, previous, current) do
    source_center = previous[edge.from].center

    source_center =
      Enum.find(
        for(candidate <- edges, candidate.from == edge.from, do: current[candidate.to].center),
        source_center,
        &(abs(&1 - source_center) <= 2)
      )

    target_center = current[edge.to].center

    if abs(source_center - target_center) <= 2 do
      {source_center, source_center}
    else
      {source_center, target_center}
    end
  end

  defp child_join_char(edge, edges, current) do
    child_centers =
      for(
        candidate <- edges,
        candidate.from == edge.from,
        uniq: true,
        do: current[candidate.to].center
      )
      |> Enum.sort()

    target_center = current[edge.to].center

    cond do
      length(child_centers) <= 1 -> "┬"
      target_center == List.first(child_centers) -> "┌"
      target_center == List.last(child_centers) -> "┐"
      true -> "┬"
    end
  end

  defp render_lr(layers, graph, width, ansi_restore) do
    layer_text =
      Enum.map(layers, fn ids ->
        ids
        |> Enum.map(fn id ->
          one_line_node(Map.fetch!(graph.nodes, id), graph.class_defs, ansi_restore)
        end)
        |> Enum.join("\n")
      end)

    layer_text
    |> Enum.with_index()
    |> Enum.map(fn {text, index} ->
      if index == length(layer_text) - 1 do
        text
      else
        label = outgoing_label(Enum.at(layers, index), Enum.at(layers, index + 1), graph)
        text <> lr_arrow(label) <> " "
      end
    end)
    |> Enum.join("")
    |> String.split("\n")
    |> Enum.flat_map(&wrap_cells(&1, width))
  end

  defp outgoing_label(from_ids, to_ids, graph) do
    Enum.find_value(graph.edges, fn edge ->
      if edge.from in from_ids and edge.to in to_ids, do: edge.label
    end)
  end

  defp lr_arrow(nil), do: "──▶"
  defp lr_arrow(""), do: "──▶"
  defp lr_arrow(label), do: "─#{label}─▶"

  defp node_box(%Node{label: label, shape: shape} = node, class_defs, ansi_restore) do
    label = label || ""
    width = String.length(label) + 2
    rendered_label = colorize(label, node_color(node, class_defs), ansi_restore)

    case shape do
      :diamond ->
        width = String.length(label) + 4

        [
          "┌" <> String.duplicate("─", width) <> "┐",
          "│‹ " <> rendered_label <> " ›│",
          "└" <> String.duplicate("─", width) <> "┘"
        ]

      :round ->
        [
          "╭" <> String.duplicate("─", width) <> "╮",
          "│ " <> rendered_label <> " │",
          "╰" <> String.duplicate("─", width) <> "╯"
        ]

      _shape ->
        [
          "┌" <> String.duplicate("─", width) <> "┐",
          "│ " <> rendered_label <> " │",
          "└" <> String.duplicate("─", width) <> "┘"
        ]
    end
  end

  defp one_line_node(%Node{label: label, shape: :diamond} = node, class_defs, ansi_restore),
    do: "<#{colorize(label, node_color(node, class_defs), ansi_restore)}>"

  defp one_line_node(%Node{label: label, shape: :round} = node, class_defs, ansi_restore),
    do: "(#{colorize(label, node_color(node, class_defs), ansi_restore)})"

  defp one_line_node(%Node{label: label} = node, class_defs, ansi_restore),
    do: "[#{colorize(label, node_color(node, class_defs), ansi_restore)}]"

  defp node_color(%Node{class_name: nil}, _class_defs), do: nil

  defp node_color(%Node{class_name: class_name}, class_defs) do
    class_defs
    |> Map.get(class_name, %{})
    |> Map.get(:color)
  end

  defp colorize(text, nil, _ansi_restore), do: text

  defp colorize(text, "#" <> hex, ansi_restore) do
    with <<red_hex::binary-size(2), green_hex::binary-size(2), blue_hex::binary-size(2)>> <- hex,
         {red, ""} <- Integer.parse(red_hex, 16),
         {green, ""} <- Integer.parse(green_hex, 16),
         {blue, ""} <- Integer.parse(blue_hex, 16) do
      "\e[38;2;#{red};#{green};#{blue}m#{text}#{ansi_restore}"
    else
      _ -> text
    end
  end

  defp fit_lines(lines, width, height) do
    lines
    |> wrap_lines(width)
    |> Enum.take(height)
  end

  defp wrap_lines(lines, width), do: Enum.flat_map(lines, &wrap_cells(&1, width))

  defp wrap_cells("", _width), do: [""]

  defp wrap_cells(line, width) do
    line
    |> BackBreeze.String.reflow(width, break: :char)
    |> String.split("\n")
    |> remove_trailing_empty_line()
  end

  defp spaces(count), do: String.duplicate(" ", max(count, 0))
  defp blank_chars(width), do: List.duplicate(" ", width)
  defp visible_length(line), do: BackBreeze.Utils.string_length(line)

  defp remove_trailing_empty_line(lines) do
    case Enum.reverse(lines) do
      ["" | rest] -> Enum.reverse(rest)
      _lines -> lines
    end
  end

  defp put_text(line, text, start) do
    text
    |> String.graphemes()
    |> Enum.with_index(start)
    |> Enum.reduce(line, fn {char, index}, line -> replace_at(line, index, char) end)
  end

  defp put_centered_text(line, text, center) do
    start = max(center - div(String.length(text), 2), 0)
    put_text(line, text, start)
  end

  defp put_horizontal_range(line, from, to) do
    Enum.reduce(from..to, line, fn index, line ->
      case Enum.at(line, index) do
        existing when existing in ["┌", "┐", "┬"] -> line
        "│" -> replace_at(line, index, "┼")
        "┼" -> line
        _char -> replace_at(line, index, "─")
      end
    end)
  end

  defp replace_connector_at(line, index, char) do
    case Enum.at(line, index) do
      "─" ->
        replace_at(line, index, char)

      existing when existing in ["┌", "┐", "┬", "┴", "│"] and existing != char ->
        replace_at(line, index, "┼")

      "┼" ->
        line

      _char ->
        replace_at(line, index, char)
    end
  end

  defp replace_at(line, index, char) when index >= 0 and index < length(line) do
    List.replace_at(line, index, char)
  end

  defp replace_at(line, _index, _char), do: line
end
