export const code = async (inputs) => {
  const policy = [inputs.new, inputs.grw, inputs.mat, inputs.clr, inputs.unknown].find(value => value && typeof value === 'object' && value.kind);
  if (!policy) throw new Error('Stage policy branch did not return a policy');
  return policy;
};
