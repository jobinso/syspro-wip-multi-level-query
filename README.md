# SYSPRO BOM Multi-Level Structure Viewer

## Overview

This SYSPRO Application Designer panel provides a comprehensive view of Bill of Materials (BOM) structures with multiple levels of sub-assemblies. It displays hierarchical BOM data in an intuitive tree format along with detailed information about materials, operations, and parent item details.

## Features

### 1. Stock Code Selector
- Enter or browse for a stock code with a BOM structure
- "Load BOM" button to retrieve and display the BOM hierarchy
- Supports parent items with complex multi-level structures

### 2. BOM Structure Tree View
- Displays complete multi-level BOM hierarchy in a tree format
- Shows parent item at the top level
- Expandable nodes for sub-assemblies and components
- Each node displays:
  - Sequence number
  - Stock code (bold)
  - Description
  - Quantity per and unit of measure (in blue)
- Icons indicate whether items have sub-assemblies

### 3. Parent Header Details Pane
Displays comprehensive information about the selected parent item:
- Stock Code
- Description and Long Description
- Part Category
- Stock UOM (Unit of Measure)
- Product Class
- Warehouse to Use
- Version, Release, and Route information
- Route Description
- Economic Batch Quantity (EBQ)
- Planner and Buyer codes

### 4. Material Allocations Pane
Lists all components and materials in the BOM:
- Component stock code
- Description
- Part category
- Unit of measure
- Sequence number
- Quantity per
- Level (depth in BOM hierarchy)

### 5. Operations Pane
Displays routing operations for the BOM:
- Operation number
- Work centre
- Operation description
- Time UOM
- Total operation cost

## Technical Details

### Application Name
- **Application ID**: BOMMULTI
- **Title**: BOM Multi-Level Structure Viewer

### Data Sources

The application uses the SYSPRO **BOMQRY** business object with four data sources:

1. **BOM multi level query**
   - Retrieves complete multi-level BOM structure
   - Level = M (Multi-level)
   - Returns parent node with all nested components

2. **BOM components multi level**
   - Extracts all components from multi-level structure
   - Repeating node for listview population
   - Shows all materials across all levels

3. **BOM operations**
   - Retrieves all routing operations
   - Includes work centers, times, and costs
   - Linked to parent node

4. **BOM parent header**
   - Single-level query for parent details only
   - Provides header information for detail pane

### Panes

The application consists of 4 main panes:

1. **BOMMULTIX0** - Tree View (left side)
   - Multi-level tree control
   - Displays hierarchical BOM structure

2. **BOMMULTIL2** - Parent Header Details (top center)
   - ListView with Field/Value pairs
   - Non-sortable detail view

3. **BOMMULTIL0** - Material Allocations (middle right)
   - ListView with component details
   - Sortable columns
   - Shows all materials with quantities

4. **BOMMULTIL1** - Operations (bottom right)
   - ListView with operation details
   - Displays routing information
   - Includes cost data

### VBScript Functions

Key functions in the application:

- **LoadBOMStructure(strStockCode)**: Main function to load complete BOM
- **GetMultiLevelBOMStructure(pStockCode)**: Calls BOMQRY business object
- **PopulateTreeView(xmlData)**: Builds hierarchical tree structure
- **BuildComponentTreeItems(componentNodes, parentIndex)**: Recursive function for tree building
- **PopulateParentHeader(xmlData)**: Fills parent detail pane
- **PopulateOperations(xmlData)**: Loads operations listview
- **PopulateMaterials(xmlData)**: Loads materials listview

### Toolbar Controls

- **38001**: Stock Code combo box (text entry)
- **58001**: Browse button (for future stock code browsing)
- **58002**: Load BOM button (triggers BOM retrieval)
- **01002**: Help button (displays help notepad)

## Usage Instructions

### Loading a BOM

1. Launch the BOMMULTI application in SYSPRO
2. Enter a stock code in the toolbar that has a BOM structure
3. Click the "Load BOM" button or press Enter
4. The application will:
   - Retrieve the multi-level BOM structure
   - Populate the tree view with the hierarchy
   - Display parent header details
   - List all materials/components
   - Show all routing operations

### Navigating the Tree

- Click the **+** icon next to an item to expand sub-assemblies
- Click the **-** icon to collapse expanded nodes
- Click on any node to view its details (future enhancement)
- The tree shows all levels of the BOM in a clear hierarchy

### Understanding the Display

**Icons in Tree View:**
- Icons 4 or 5: Item has sub-assemblies (expandable)
- Icon 1: Leaf node (no sub-assemblies)
- Icon 30: Operation node

**Material Allocations:**
- Level 1: Direct components of parent
- Level 2+: Sub-assembly components
- Sequence: Order of assembly
- Qty Per: Quantity required per parent unit

**Operations:**
- Listed in sequence order
- Shows work center for each operation
- Total cost includes labor, overhead, and subcontract costs

## File Structure

```
/syspro-wip-multi-level-query/
├── BOMMultiLevelPanel.xml       # Main application file
├── README.md                     # This documentation
└── ref/                          # Reference materials
    ├── schema/
    │   ├── BOMQRY.XSD           # Input schema
    │   ├── BOMQRYOUT.XSD        # Output schema
    │   ├── BOMQRY.XML           # Sample input
    │   └── BOMQRYOUT.XML        # Sample output
    ├── Application Design Example BOM Material Structure.txt
    ├── Application Design Example SCript BOM Material Structure.txt
    └── syspro-*.pdf             # Developer documentation
```

## Installation

1. Copy `BOMMultiLevelPanel.xml` to your SYSPRO application directory
2. Import the application using SYSPRO Application Designer
3. The application will be available as "BOMMULTI" in SYSPRO

## Customization Options

### Adding More Fields

To add more fields to any pane:

1. **Parent Header Details**: Edit `PopulateParentHeader()` function to add more Field/Value pairs
2. **Material Allocations**: Update `BOMMULTIL0` listview definition and add BindColumn entries
3. **Operations**: Update `BOMMULTIL1` listview definition and add BindColumn entries

### Changing Query Options

Edit the data source XMLIN to modify:
- **Route**: Change from `0` to specific route number
- **UnitOfMeasure**: Change from `S` (Stocking) to `A` (Alternate), `O` (Other), or `M` (Manufacturing)
- **CostBasis**: Change from `B` (BOM) to `W` (What-if)
- **IncludeComponentNarrations**: Set to `Y` to include component notes
- **IncludeOperationNarrations**: Set to `Y` to include operation notes

### Tree View Enhancement

The current implementation loads the complete multi-level structure at once. For very large BOMs, you could modify it to use lazy loading (only load child nodes when expanded) by:

1. Setting `Level=S` (single-level) in the data source
2. Implementing the `TreeExpand` event to query child components on demand
3. This approach is demonstrated in the reference sample `SAMTV2`

## Troubleshooting

### No Data Displayed
- Verify the stock code exists in SYSPRO
- Ensure the stock code has a BOM defined
- Check that BOMQRY business object is available
- Review error messages in the message box

### Tree Not Expanding
- Verify icons are set correctly (4 or 5 for items with children)
- Check HasChildren attribute is set to 'Y'
- Ensure component data includes SubAssembly nodes for multi-level items

### Missing Operations or Materials
- Verify the parent item has operations defined in routing
- Check that components are defined in the BOM
- Ensure data sources are configured with correct node paths

## Known Limitations

1. The tree view currently shows all levels at once - for very large BOMs (>1000 items), consider implementing lazy loading
2. Clicking on a child node in the tree doesn't currently load that item's specific BOM (can be added as enhancement)
3. Browse button functionality is not implemented (placeholder for future integration)

## Future Enhancements

Potential improvements for future versions:

1. **Interactive Tree Nodes**: Click on any component to load its BOM structure
2. **Stock Code Browse**: Integrate SYSPRO stock code browse functionality
3. **Export to Excel**: Add button to export BOM structure to Excel
4. **Print Preview**: Add formatted print layout for BOM reports
5. **Cost Rollup**: Calculate and display total rolled-up costs
6. **Where-Used**: Add ability to show where a component is used
7. **BOM Comparison**: Compare two BOMs side-by-side
8. **Phantom Items**: Special handling for phantom components
9. **Visual Indicators**: Color-coding for obsolete, on-hold, or special items
10. **Search/Filter**: Add ability to search for specific components in the tree

## Support and References

- SYSPRO Application Designer Documentation
- BOMQRY Business Object Reference (see ref/ folder)
- Sample files in ref/ directory provide additional examples

## Version History

- **v1.0** (2025-11-12): Initial release with multi-level BOM tree view and three detail panes

## Author

Generated using SYSPRO Application Designer based on user requirements.
