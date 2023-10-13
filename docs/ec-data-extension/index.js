'use strict'

module.exports.register = function() {
  this.on('contentAggregated', async ({ contentAggregate }) => {
    const yaml = this.require('js-yaml')

    const rhtap = contentAggregate.find(c => c.name == 'rhtap-policy')
    const ruleDataFile = rhtap.files.find(f => f.src.basename === 'rule_data.yml')
    const ruleData = yaml.load(ruleDataFile.contents)

    const requiredTasksFile = rhtap.files.find(f => f.src.basename === 'required_tasks.yml')
    const requiredTasks = yaml.load(requiredTasksFile.contents)

    const Handlebars = this.require('handlebars')

    const ruleDataTemplate = rhtap.files.find(f => f.path.endsWith('rule_data.hbs'))
    const template = Handlebars.compile(ruleDataTemplate.contents.toString());

    const context = {
      rule_data_src: ruleDataFile.src,
      required_tasks_src: requiredTasksFile.src,
      ...ruleData,
      required_tasks: requiredTasks
    }

    rhtap.files.push({
        contents: Buffer.from(template(context)),
        path: 'modules/ROOT/pages/index.adoc',
        src: {
          path: 'modules/ROOT/pages/index.adoc',
          basename: 'index.adoc',
          stem: 'index',
          extname: '.adoc'
        }
      })
  })
}
