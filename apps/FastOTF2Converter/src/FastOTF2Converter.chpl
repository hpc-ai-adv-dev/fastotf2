// Copyright Hewlett Packard Enterprise Development LP.

module FastOTF2Converter {
  use ConverterArgs;
  use Strategy_Serial;
  use Strategy_LocBlock;
  use Strategy_LocGroupBlock;
  use Strategy_LocGroupDistBlock;
  // Future strategies:
  // use Strategy_LocDynamic;
  // use Strategy_LocGroupDynamic;
  // use Strategy_LocGroupBlockDistDynamic;
  // use Strategy_LocGroupDistBalanced;

  proc main(args: [] string) throws {
    const conf = parseConverterArgs(args);
    validatePaths(conf);

    select conf.strategy {
      when "serial" do
        Strategy_Serial.run(conf);
      when "loc_block" do
        Strategy_LocBlock.run(conf);
      when "loc_dynamic" do
        halt("Strategy loc_dynamic not yet implemented");
      when "locgroup_block" do
        Strategy_LocGroupBlock.run(conf);
      when "locgroup_dynamic" do
        halt("Strategy locgroup_dynamic not yet implemented");
      when "locgroup_dist_block" do
        Strategy_LocGroupDistBlock.run(conf);
      when "locgroup_blockdist_dynamic" do
        halt("Strategy locgroup_blockdist_dynamic not yet implemented");
      when "locgroup_dist_balanced" do
        halt("Strategy locgroup_dist_balanced not yet implemented");
      otherwise
        halt("Unknown strategy: ", conf.strategy,
             ". Use one of: serial, loc_block, loc_dynamic, locgroup_block, ",
             "locgroup_dynamic, locgroup_dist_block, ",
             "locgroup_blockdist_dynamic, locgroup_dist_balanced");
    }
  }
}
